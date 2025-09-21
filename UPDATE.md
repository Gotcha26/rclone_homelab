```text
                             ┌───────────────┐
                             │   Branche ?   │
                             └───────┬───────┘
                                     │
                  ┌──────────────────┴──────────────────┐
                  │                                     │
                 main                                  autre
                  │                                     │
     ┌────────────┴─────────────┐        Comparer HEAD avec origin/<branche>
     │ Dernier tag existant ?    │
     │                            │
     │  ┌───────────────┐         │
     │  │ HEAD < tag ?  │         │
     │  └───────┬───────┘         │
     │          │                   │
     │    Oui → "Nouvelle release disponible" (MAJ possible)  
     │    Non → HEAD = tag → "Version installée à jour"  
     │          HEAD > tag → "Commits non officiels, MAJ automatique non recommandée"
     │
Autres branches (dev, expérimental, etc.)
-----------------------------------------
HEAD < remote ? → "Mise à jour disponible" (MAJ possible)
HEAD = remote ? → "Version installée à jour"
HEAD > remote ? → "Commits plus récents que l’origine, MAJ automatique non recommandée"



**Légende :**  
- **main** → suit les **tags**, HEAD ne doit pas dépasser la dernière release.  
- **dev/autres** → suit l’**origine**, MAJ possible ou avertissement si commit plus récent.  
- `result_code` reflète le risque / action à entreprendre : 0 = stable / pas de MAJ, 1 = MAJ disponible.  

flowchart TD
    A[HEAD = version installée] --> B{Branche ?}

    B --> |main| C{Dernier tag existant ?}
    B --> |autre| D[Comparer HEAD avec origin/<branche>]

    %% Main branch
    C --> |Oui| E{HEAD < dernier tag ?}
    C --> |Non| F[Impossible de vérifier la MAJ]

    E --> |Oui| G[Nouvelle release disponible → MAJ possible]
    E --> |Non| H{HEAD = dernier tag ?}
    H --> |Oui| I[Version installée à jour]
    H --> |Non| J[Commits non officiels → MAJ automatique non recommandée]

    %% Autre branche
    D --> K{HEAD < remote ?}
    K --> |Oui| L[Mise à jour disponible → MAJ possible]
    K --> |Non| M{HEAD = remote ?}
    M --> |Oui| N[Version installée à jour]
    M --> |Non| O[Commits plus récents que l'origine → MAJ automatique non recommandée]
