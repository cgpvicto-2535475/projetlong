-- Base existante uniquement. Sauvegarder projet_long et arrêter les écritures
-- pendant toute la migration : MySQL valide automatiquement les ALTER TABLE.
-- Le dernier DROP TABLE retire l'ancienne association après vérification.
USE projet_long;

DROP PROCEDURE IF EXISTS migrer_commandes_projet_long;
DELIMITER $$
CREATE PROCEDURE migrer_commandes_projet_long()
migration: BEGIN
    DECLARE mode_securise BOOL DEFAULT @@SESSION.sql_safe_updates;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET SESSION sql_safe_updates = mode_securise;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE()
                   AND table_name = 'commandes_pizza') THEN
        IF (SELECT COUNT(*) FROM information_schema.table_constraints
            WHERE constraint_schema = DATABASE()
              AND ((table_name = 'commandes' AND constraint_name IN
                    ('fk_commandes_pizzas', 'chk_commandes_quantite', 'confirmation'))
                OR (table_name = 'garnitures_pizza' AND constraint_name IN
                    ('uq_position_garniture', 'chk_position_garniture')))) = 5 THEN
            SELECT 'Le modele avec une pizza par commande est deja en place.' AS resultat;
            LEAVE migration;
        END IF;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Association commandes_pizza absente et schema incomplet.';
    END IF;

    -- Afficher les identifiants incompatibles avant de modifier le schéma.
    SELECT c.id, COUNT(cp.pizza_id) AS nombre_de_pizzas
    FROM commandes c LEFT JOIN commandes_pizza cp ON cp.commande_id = c.id
    GROUP BY c.id HAVING COUNT(cp.pizza_id) <> 1 OR MIN(cp.quantite) <= 0;

    SELECT pizza_id, COUNT(*) AS nombre_de_garnitures
    FROM garnitures_pizza GROUP BY pizza_id HAVING COUNT(*) > 4;

    IF EXISTS (
        SELECT c.id FROM commandes c
        LEFT JOIN commandes_pizza cp ON cp.commande_id = c.id
        GROUP BY c.id HAVING COUNT(cp.pizza_id) <> 1 OR MIN(cp.quantite) <= 0
    ) OR EXISTS (
        SELECT pizza_id FROM garnitures_pizza GROUP BY pizza_id HAVING COUNT(*) > 4
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Migration interrompue : examiner les commandes ou les garnitures signalees.';
    END IF;

    -- Ces vérifications permettent de reprendre après une interruption.
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = DATABASE()
                   AND table_name = 'commandes' AND column_name = 'pizza_id') THEN
        ALTER TABLE commandes ADD pizza_id INT NULL, ADD quantite INT NULL,
            ADD confirmation CHAR(32) UNIQUE;
    END IF;

    -- La copie porte volontairement sur toutes les commandes (Workbench).
    SET SESSION sql_safe_updates = 0;
    UPDATE commandes c JOIN commandes_pizza cp ON cp.commande_id = c.id
    SET c.pizza_id = cp.pizza_id, c.quantite = cp.quantite;
    SET SESSION sql_safe_updates = mode_securise;

    IF EXISTS (
        SELECT 1 FROM commandes c LEFT JOIN commandes_pizza cp ON cp.commande_id = c.id
        WHERE cp.commande_id IS NULL OR NOT (c.pizza_id <=> cp.pizza_id)
              OR NOT (c.quantite <=> cp.quantite)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La copie des commandes ne correspond pas aux lignes originales.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_schema = DATABASE()
                   AND table_name = 'commandes' AND constraint_name = 'fk_commandes_pizzas') THEN
        ALTER TABLE commandes MODIFY pizza_id INT NOT NULL, MODIFY quantite INT NOT NULL,
            ADD CONSTRAINT fk_commandes_pizzas FOREIGN KEY (pizza_id) REFERENCES pizzas(id),
            ADD CONSTRAINT chk_commandes_quantite CHECK (quantite > 0);
    END IF;

    -- Numéroter les garnitures existantes sans changer leurs identifiants.
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = DATABASE()
                   AND table_name = 'garnitures_pizza' AND column_name = 'position_garniture') THEN
        ALTER TABLE garnitures_pizza ADD position_garniture TINYINT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_schema = DATABASE()
                   AND table_name = 'garnitures_pizza' AND constraint_name = 'uq_position_garniture') THEN
        SET SESSION sql_safe_updates = 0;
        UPDATE garnitures_pizza gp
        JOIN (SELECT pizza_id, garniture_id,
                     ROW_NUMBER() OVER (PARTITION BY pizza_id ORDER BY garniture_id) AS rang
              FROM garnitures_pizza) positions
          ON positions.pizza_id = gp.pizza_id AND positions.garniture_id = gp.garniture_id
        SET gp.position_garniture = positions.rang;
        SET SESSION sql_safe_updates = mode_securise;
        ALTER TABLE garnitures_pizza MODIFY position_garniture TINYINT NOT NULL,
            ADD CONSTRAINT chk_position_garniture CHECK (position_garniture BETWEEN 1 AND 4),
            ADD CONSTRAINT uq_position_garniture UNIQUE (pizza_id, position_garniture);
    END IF;

    -- Aucune insertion dans commandes : les anciennes livraisons conservent leur état.
    DROP TABLE commandes_pizza;
END$$
DELIMITER ;
CALL migrer_commandes_projet_long();
DROP PROCEDURE migrer_commandes_projet_long;
