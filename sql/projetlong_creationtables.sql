-- Installation neuve seulement. Pour une base existante, utiliser projetlong_migration.sql.
CREATE DATABASE IF NOT EXISTS projet_long;
USE projet_long;

CREATE TABLE IF NOT EXISTS clients(
	id INT AUTO_INCREMENT NOT NULL,
    nom_client VARCHAR(50) NOT NULL,
    numero_telephone VARCHAR(20) NOT NULL,
    adresse_livraison VARCHAR(100) NOT NULL,
    CONSTRAINT pk_clients PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS croutes(
	id INT AUTO_INCREMENT NOT NULL, 
    nom_croute VARCHAR(50) NOT NULL,
    
    CONSTRAINT pk_croutes PRIMARY KEY (id),
    CONSTRAINT uq_croutes_nom UNIQUE (nom_croute)
);

CREATE TABLE IF NOT EXISTS sauces(
    id INT AUTO_INCREMENT NOT NULL,
    nom_sauce VARCHAR(50) NOT NULL,

    CONSTRAINT pk_sauces PRIMARY KEY (id),
    CONSTRAINT uq_sauces_nom UNIQUE (nom_sauce)
);

CREATE TABLE IF NOT EXISTS garnitures(
	id INT AUTO_INCREMENT NOT NULL,
    nom_garniture VARCHAR(255) NOT NULL,
    
    CONSTRAINT pk_garnitures PRIMARY KEY (id),
    CONSTRAINT uq_garnitures_nom UNIQUE (nom_garniture)
);



CREATE TABLE IF NOT EXISTS pizzas(
	id INT AUTO_INCREMENT NOT NULL ,
    nom_pizza VARCHAR(50) NOT NULL,
    croute_id INT NOT NULL,
    sauce_id INT NOT NULL,
    
    CONSTRAINT pk_pizzas PRIMARY KEY (id),
    
    CONSTRAINT fk_pizzas_croutes FOREIGN KEY (croute_id) references croutes(id),
    CONSTRAINT fk_pizzas_sauces FOREIGN KEY (sauce_id) REFERENCES sauces(id)
);

CREATE TABLE IF NOT EXISTS commandes(
	id INT AUTO_INCREMENT NOT NULL,
    date_commande DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    client_id INT NOT NULL,
    pizza_id INT NOT NULL,
    quantite INT NOT NULL,
    confirmation CHAR(32) UNIQUE,
    CONSTRAINT chk_commandes_quantite CHECK (quantite > 0),
    CONSTRAINT fk_commandes_pizzas FOREIGN KEY (pizza_id) REFERENCES pizzas(id),
    
    CONSTRAINT pk_commandes PRIMARY KEY (id),
    
    CONSTRAINT fk_commandes_clients FOREIGN KEY (client_id) REFERENCES clients(id)
);

CREATE TABLE IF NOT EXISTS garnitures_pizza(
	pizza_id INT NOT NULL,
    garniture_id INT NOT NULL,
    -- Quatre emplacements par pizza, même pour les insertions faites hors de Flask.
    position_garniture TINYINT NOT NULL,
    CONSTRAINT chk_position_garniture CHECK (position_garniture BETWEEN 1 AND 4),
    CONSTRAINT uq_position_garniture UNIQUE (pizza_id, position_garniture),
    
    CONSTRAINT pk_garnitures_pizza PRIMARY KEY (pizza_id, garniture_id),

    CONSTRAINT fk_garnitures_pizza_pizzas FOREIGN KEY (pizza_id) REFERENCES pizzas(id),

    CONSTRAINT fk_garnitures_pizza_garnitures FOREIGN KEY (garniture_id) REFERENCES garnitures(id)
);

CREATE TABLE IF NOT EXISTS livraisons_en_attente (
    commande_id INT NOT NULL,
    date_ajout DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_livraisons_en_attente
        PRIMARY KEY (commande_id),

    CONSTRAINT fk_livraisons_commandes
        FOREIGN KEY (commande_id)
        REFERENCES commandes(id)
);

DELIMITER $$

CREATE TRIGGER trg_commande_en_attente
AFTER INSERT ON commandes
FOR EACH ROW
BEGIN

    INSERT INTO livraisons_en_attente (commande_id, date_ajout) VALUES (NEW.id, NOW());

END$$

DELIMITER ;
