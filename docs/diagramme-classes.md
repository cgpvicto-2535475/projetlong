# Diagramme de classes de la pizzeria

```mermaid
classDiagram
    direction TB

    class Client {
        +INT id PK
        +VARCHAR nom_client
        +VARCHAR numero_telephone
        +VARCHAR adresse_livraison
    }
    class Commande {
        +INT id PK
        +DATETIME date_commande
        +INT client_id FK
        +INT pizza_id FK
        +INT quantite
        +CHAR confirmation UK
    }
    class Pizza {
        +INT id PK
        +VARCHAR nom_pizza
        +INT croute_id FK
        +INT sauce_id FK
    }
    class Croute {
        +INT id PK
        +VARCHAR nom_croute UK
    }
    class Sauce {
        +INT id PK
        +VARCHAR nom_sauce UK
    }
    class GarniturePizza {
        +INT pizza_id PK FK
        +INT garniture_id PK FK
        +TINYINT position_garniture
    }
    class Garniture {
        +INT id PK
        +VARCHAR nom_garniture UK
    }
    class LivraisonEnAttente {
        +INT commande_id PK FK
        +DATETIME date_ajout
    }

    Client "1" -- "0..*" Commande : passe
    Pizza "1" -- "0..*" Commande : figure dans
    Croute "1" -- "0..*" Pizza : compose
    Sauce "1" -- "0..*" Pizza : compose
    Pizza "1" -- "0..4" GarniturePizza : contient
    Garniture "1" -- "0..*" GarniturePizza : est choisie
    Commande "1" -- "0..1" LivraisonEnAttente : attend la livraison
```

`PK` indique une clé primaire, `FK` une clé étrangère et `UK` une valeur unique.

- Chaque commande référence une seule pizza. `quantite` indique le nombre d’exemplaires identiques et doit être supérieure à zéro.
- Une pizza a une croûte, une sauce et jusqu’à quatre garnitures distinctes. Dans `garnitures_pizza`, une position entre 1 et 4 ne peut être utilisée qu’une fois par pizza.
- Le déclencheur `trg_commande_en_attente` crée l’entrée de livraison lors de l’insertion d’une commande. Quand la livraison est complétée, l’entrée sort de la file et la commande reste en base.
- La colonne `confirmation` contient le jeton utilisé par Flask pour empêcher un double enregistrement. Les commandes migrées peuvent avoir un jeton `NULL`.
