import os
import secrets

import mysql.connector
from dotenv import load_dotenv
from flask import Flask, flash, redirect, render_template, request, session, url_for
from mysql.connector import errorcode

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY") or secrets.token_hex(32)


def connecter_bd():
    return mysql.connector.connect(
        host=os.getenv("DB_HOST"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        database=os.getenv("DB_NAME"),
        port=int(os.getenv("DB_PORT", "3306")),
        autocommit=False,
    )


@app.errorhandler(mysql.connector.Error)
def erreur_mysql(erreur):
    app.logger.error("Erreur MySQL %s", erreur.errno)
    message = "Une erreur de base de données est survenue."
    return render_template("erreur.html", erreur=message), 503


def catalogue():
    db = connecter_bd()
    curseur = None
    try:
        curseur = db.cursor()
        curseur.execute("SELECT id, nom_croute FROM croutes ORDER BY id")
        croutes = dict(curseur.fetchall())

        curseur.execute("SELECT id, nom_sauce FROM sauces ORDER BY id")
        sauces = dict(curseur.fetchall())

        curseur.execute("SELECT id, nom_garniture FROM garnitures ORDER BY id")
        garnitures = dict(curseur.fetchall())
        return croutes, sauces, garnitures
    finally:
        if curseur is not None:
            curseur.close()
        db.close()


def valider(formulaire, croutes, sauces, garnitures):
    garnitures_saisies = formulaire.getlist("garnitures")
    choix = {
        "nom_client": formulaire.get("nom_client", "").strip(),
        "numero_telephone": formulaire.get("numero_telephone", "").strip(),
        "adresse_livraison": formulaire.get("adresse_livraison", "").strip(),
        "croute_id": formulaire.get("croute_id", type=int),
        "sauce_id": formulaire.get("sauce_id", type=int),
        "garnitures": formulaire.getlist("garnitures", type=int),
        "quantite": formulaire.get("quantite", ""),
    }

    if not 1 <= len(choix["nom_client"]) <= 50:
        return choix, "Ton nom doit contenir de 1 à 50 caractères."
    if not 1 <= len(choix["numero_telephone"]) <= 20:
        return choix, "Ton numéro de téléphone doit contenir de 1 à 20 caractères."
    if not 1 <= len(choix["adresse_livraison"]) <= 100:
        return choix, "Ton adresse doit contenir de 1 à 100 caractères."
    if choix["croute_id"] not in croutes:
        return choix, "Choisis une croûte du menu."
    if choix["sauce_id"] not in sauces:
        return choix, "Choisis une sauce du menu."

    if len(garnitures_saisies) > 4:
        return choix, "Choisis au maximum quatre garnitures."
    if len(garnitures_saisies) != len(choix["garnitures"]):
        return choix, "Garniture inconnue."
    garnitures_vues = []
    for garniture_id in choix["garnitures"]:
        if garniture_id not in garnitures or garniture_id in garnitures_vues:
            return choix, "Chaque garniture doit être un choix distinct du menu."
        garnitures_vues.append(garniture_id)

    quantite = formulaire.get("quantite", type=int)
    if quantite is None or not 1 <= quantite <= 2147483647:
        return choix, "La quantité doit être un entier positif compatible avec MySQL INT."
    choix["quantite"] = quantite
    return choix, None


@app.route("/", methods=["GET", "POST"])
def index():
    croutes, sauces, garnitures = catalogue()
    choix = session.get("commande", {})
    erreur = None
    statut = 200

    if request.method == "POST":
        session.pop("confirmation", None)
        choix, erreur = valider(request.form, croutes, sauces, garnitures)
        if erreur is None:
            session["commande"] = choix
            session["confirmation"] = secrets.token_hex(16)
            return redirect(url_for("resume"), code=303)
        statut = 400

    return render_template(
        "index.html", choix=choix, croutes=croutes, sauces=sauces,
        garnitures=garnitures, erreur=erreur,
    ), statut


@app.route("/resume")
def resume():
    choix = session.get("commande")
    if not choix or not session.get("confirmation"):
        return redirect(url_for("index"), code=303)

    croutes, sauces, garnitures = catalogue()
    ingredients_disponibles = choix["croute_id"] in croutes and choix["sauce_id"] in sauces
    for garniture_id in choix["garnitures"]:
        if garniture_id not in garnitures:
            ingredients_disponibles = False
            break

    if not ingredients_disponibles:
        session.pop("confirmation", None)
        flash("Un ingrédient du résumé est indisponible. Vérifie tes choix.")
        return redirect(url_for("index"), code=303)
    return render_template(
        "resume.html", choix=choix, croutes=croutes, sauces=sauces, garnitures=garnitures,
    )


@app.route("/modifier", methods=["POST"])
def modifier():
    confirmation = session.get("confirmation")
    if confirmation and request.form.get("confirmation") == confirmation:
        session.pop("confirmation")
    return redirect(url_for("index"), code=303)


def enregistrer(choix, confirmation):
    db = connecter_bd()
    curseur = None
    try:
        curseur = db.cursor()
        requete = """
            INSERT INTO clients (nom_client, numero_telephone, adresse_livraison)
            VALUES (%(nom_client)s, %(numero_telephone)s, %(adresse_livraison)s)
        """
        parametres = {
            "nom_client": choix["nom_client"],
            "numero_telephone": choix["numero_telephone"],
            "adresse_livraison": choix["adresse_livraison"],
        }
        curseur.execute(requete, parametres)
        client_id = curseur.lastrowid

        requete = """
            INSERT INTO pizzas (nom_pizza, croute_id, sauce_id)
            VALUES ('Personnalisée', %(croute_id)s, %(sauce_id)s)
        """
        parametres = {"croute_id": choix["croute_id"], "sauce_id": choix["sauce_id"]}
        curseur.execute(requete, parametres)
        pizza_id = curseur.lastrowid

        requete = """
            INSERT INTO garnitures_pizza (pizza_id, garniture_id, position_garniture)
            VALUES (%(pizza_id)s, %(garniture_id)s, %(position)s)
        """
        position = 1
        for garniture_id in choix["garnitures"]:
            curseur.execute(requete, {
                "pizza_id": pizza_id,
                "garniture_id": garniture_id,
                "position": position,
            })
            position += 1

        requete = """
            INSERT INTO commandes (client_id, pizza_id, quantite, confirmation)
            VALUES (%(client_id)s, %(pizza_id)s, %(quantite)s, %(confirmation)s)
        """
        parametres = {
            "client_id": client_id,
            "pizza_id": pizza_id,
            "quantite": choix["quantite"],
            "confirmation": confirmation,
        }
        curseur.execute(requete, parametres)
        commande_id = curseur.lastrowid
        db.commit()
        return commande_id

    except mysql.connector.Error as erreur:
        db.rollback()
        if erreur.errno == errorcode.ER_NO_REFERENCED_ROW_2:
            return None
        if curseur is not None and erreur.errno == errorcode.ER_DUP_ENTRY:
            requete = "SELECT id FROM commandes WHERE confirmation = %(confirmation)s"
            curseur.execute(requete, {"confirmation": confirmation})
            commande = curseur.fetchone()
            if commande:
                return commande[0]
        raise
    finally:
        if curseur is not None:
            curseur.close()
        db.close()


@app.route("/confirmer", methods=["POST"])
def confirmer():
    choix = session.get("commande")
    confirmation = session.get("confirmation")
    if not choix or not confirmation or request.form.get("confirmation") != confirmation:
        flash("Ce résumé a expiré ou a déjà été confirmé.")
        return redirect(url_for("index"), code=303)

    commande_id = enregistrer(choix, confirmation)
    session.pop("confirmation")
    if commande_id is None:
        flash("Un ingrédient du résumé est indisponible. Vérifie tes choix.")
        return redirect(url_for("index"), code=303)

    session.pop("commande")
    flash(f"Commande nº {commande_id} enregistrée.")
    return redirect(url_for("livraisons"), code=303)


@app.route("/livraisons")
def livraisons():
    requete = """
        SELECT c.id, c.quantite, l.date_ajout, cl.nom_client, cl.numero_telephone,
               cl.adresse_livraison, cr.nom_croute, s.nom_sauce,
               (SELECT GROUP_CONCAT(g.nom_garniture ORDER BY gp.position_garniture SEPARATOR ', ')
                  FROM garnitures_pizza gp JOIN garnitures g ON g.id = gp.garniture_id
                 WHERE gp.pizza_id = p.id) AS garnitures
        FROM livraisons_en_attente l
        JOIN commandes c ON c.id = l.commande_id
        JOIN clients cl ON cl.id = c.client_id
        JOIN pizzas p ON p.id = c.pizza_id
        JOIN croutes cr ON cr.id = p.croute_id
        JOIN sauces s ON s.id = p.sauce_id
        ORDER BY l.date_ajout, c.id
    """
    db = connecter_bd()
    curseur = None
    try:
        curseur = db.cursor(dictionary=True)
        curseur.execute(requete)
        commandes = curseur.fetchall()
    finally:
        if curseur is not None:
            curseur.close()
        db.close()

    if "jeton_livraison" not in session:
        session["jeton_livraison"] = secrets.token_hex(16)
    return render_template("livraisons.html", livraisons=commandes)


@app.route("/livraisons/<int:commande_id>/terminer", methods=["POST"])
def terminer_livraison(commande_id):
    jeton = session.get("jeton_livraison")
    if not jeton or request.form.get("jeton") != jeton:
        return render_template("erreur.html", erreur="Ouvre la liste des livraisons et réessaie."), 400

    requete = "DELETE FROM livraisons_en_attente WHERE commande_id = %(commande_id)s"
    parametres = {"commande_id": commande_id}
    db = connecter_bd()
    curseur = None
    try:
        curseur = db.cursor()
        curseur.execute(requete, parametres)
        livraison_retiree = curseur.rowcount
        db.commit()
    except mysql.connector.Error:
        db.rollback()
        raise
    finally:
        if curseur is not None:
            curseur.close()
        db.close()

    if livraison_retiree:
        flash("Livraison complétée.")
    else:
        flash("Cette commande ne figure plus dans la liste.")
    return redirect(url_for("livraisons"), code=303)


if __name__ == "__main__":
    app.run()
