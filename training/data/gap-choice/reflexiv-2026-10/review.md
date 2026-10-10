# Reflexive items from the planner: review sheet

Seed 7. 113 Akkusativ oder Dativ?, 100 Die richtige Person; 213 pass the gate, 213 in `candidates.json`.

The German comes from the verb table, never from a model. Read each row: is it natural German a teacher would put on a worksheet, and is the English twin right? Mark `reads_right` (✓/✗) and a `note` in `review.csv`. A ✗ names a table row to fix (the verb's forms, its objects, a tail, the English pattern); then the pack is regenerated with the same seed.

| focus | items | pass | candidates | Akk | Dat | inline |
|---|---:|---:|---:|---:|---:|---:|
| Akkusativ oder Dativ? | 113 | 113 | 113 | 56 | 57 | 28 |
| Die richtige Person | 100 | 100 | 100 | 50 | 50 | 25 |

## Akkusativ oder Dativ?

persons: 1sg 56, 2sg 57

### sich abtrocknen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich trockne mich ab. | I dry myself off. | mich / mir / dich / dir | rx-s-case-abtrocknen-1sg |
|  | Ich trockne mir die Haare ab. | I dry my hair. | mich / mir / dich / dir | rx-s-case-abtrocknen-1sg-haar |
|  | Ich trockne mir die Hände ab. | I dry my hands. | mich / mir / dich / dir | rx-s-case-abtrocknen-1sg-hand |
|  | Du trocknest dich ab. | You dry yourself off. | dir / dich (inline) | rx-s-case-abtrocknen-2sg |
|  | Du trocknest dir die Haare ab. | You dry your hair. | mich / mir / dich / dir | rx-s-case-abtrocknen-2sg-haar |
|  | Du trocknest dir die Hände ab. | You dry your hands. | mich / mir / dich / dir | rx-s-case-abtrocknen-2sg-hand |

### sich ansehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich sehe mir das Bild an. | I look at the picture. | mich / mir / dich / dir | rx-s-case-ansehen-1sg-bild |
|  | Ich sehe mir das Foto an. | I look at the photo. | mich / mir (inline) | rx-s-case-ansehen-1sg-foto |
|  | Du siehst dir das Bild an. | You look at the picture. | mich / mir / dich / dir | rx-s-case-ansehen-2sg-bild |
|  | Du siehst dir das Foto an. | You look at the photo. | dir / dich (inline) | rx-s-case-ansehen-2sg-foto |

### sich anziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich an. | I get dressed. | mich / mir / dich / dir | rx-s-case-anziehen-1sg |
|  | Ich ziehe mir den Mantel an. | I put on my coat. | mich / mir / dich / dir | rx-s-case-anziehen-1sg-mantel |
|  | Ich ziehe mir die Schuhe an. | I put on my shoes. | mich / mir (inline) | rx-s-case-anziehen-1sg-schuh |
|  | Du ziehst dich an. | You get dressed. | mich / mir / dich / dir | rx-s-case-anziehen-2sg |
|  | Du ziehst dir die Jacke an. | You put on your jacket. | mich / mir / dich / dir | rx-s-case-anziehen-2sg-jacke |
|  | Du ziehst dir den Mantel an. | You put on your coat. | mich / mir / dich / dir | rx-s-case-anziehen-2sg-mantel |
|  | Du ziehst dir die Schuhe an. | You put on your shoes. | mich / mir / dich / dir | rx-s-case-anziehen-2sg-schuh |

### sich ausziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich aus. | I get undressed. | mich / mir / dich / dir | rx-s-case-ausziehen-1sg |
|  | Ich ziehe mir die Jacke aus. | I take off my jacket. | mich / mir (inline) | rx-s-case-ausziehen-1sg-jacke |
|  | Ich ziehe mir den Mantel aus. | I take off my coat. | mich / mir / dich / dir | rx-s-case-ausziehen-1sg-mantel |
|  | Ich ziehe mir die Schuhe aus. | I take off my shoes. | mich / mir / dich / dir | rx-s-case-ausziehen-1sg-schuh |
|  | Du ziehst dich aus. | You get undressed. | mich / mir / dich / dir | rx-s-case-ausziehen-2sg |
|  | Du ziehst dir die Jacke aus. | You take off your jacket. | mich / mir / dich / dir | rx-s-case-ausziehen-2sg-jacke |
|  | Du ziehst dir den Mantel aus. | You take off your coat. | mich / mir / dich / dir | rx-s-case-ausziehen-2sg-mantel |
|  | Du ziehst dir die Schuhe aus. | You take off your shoes. | mich / mir / dich / dir | rx-s-case-ausziehen-2sg-schuh |

### sich beeilen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich beeile mich heute. | I hurry today. | mich / mir (inline) | rx-s-case-beeilen-1sg-t-heute |
|  | Ich beeile mich jetzt. | I hurry now. | mich / mir / dich / dir | rx-s-case-beeilen-1sg-t-jetzt |
|  | Du beeilst dich heute. | You hurry today. | mich / mir / dich / dir | rx-s-case-beeilen-2sg-t-heute |
|  | Du beeilst dich jetzt. | You hurry now. | mich / mir / dich / dir | rx-s-case-beeilen-2sg-t-jetzt |

### sich duschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich dusche mich am Morgen. | I shower in the morning. | mich / mir / dich / dir | rx-s-case-duschen-1sg-t-am-morgen |
|  | Ich dusche mich nach dem Sport. | I shower after sport. | mich / mir / dich / dir | rx-s-case-duschen-1sg-t-nach-dem-sport |
|  | Du duschst dich am Morgen. | You shower in the morning. | dich / dir (inline) | rx-s-case-duschen-2sg-t-am-morgen |
|  | Du duschst dich nach dem Sport. | You shower after sport. | mich / mir / dich / dir | rx-s-case-duschen-2sg-t-nach-dem-sport |

### sich entschuldigen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich entschuldige mich bei der Nachbarin. | I apologise to the neighbour. | mich / mir (inline) | rx-s-case-entschuldigen-1sg-t-bei-der-nachbarin |
|  | Ich entschuldige mich beim Lehrer. | I apologise to the teacher. | mich / mir (inline) | rx-s-case-entschuldigen-1sg-t-beim-lehrer |
|  | Du entschuldigst dich bei der Nachbarin. | You apologise to the neighbour. | mich / mir / dich / dir | rx-s-case-entschuldigen-2sg-t-bei-der-nachbarin |
|  | Du entschuldigst dich beim Lehrer. | You apologise to the teacher. | mich / mir / dich / dir | rx-s-case-entschuldigen-2sg-t-beim-lehrer |

### sich erholen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich erhole mich am Wochenende. | I rest at the weekend. | mich / mir / dich / dir | rx-s-case-erholen-1sg-t-am-wochenende |
|  | Ich erhole mich im Urlaub. | I rest on holiday. | mich / mir / dich / dir | rx-s-case-erholen-1sg-t-im-urlaub |
|  | Du erholst dich im Urlaub. | You rest on holiday. | mich / mir / dich / dir | rx-s-case-erholen-2sg-t-im-urlaub |

### sich erinnern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich erinnere mich an den Sommer. | I remember the summer. | mich / mir / dich / dir | rx-s-case-erinnern-1sg-t-an-den-sommer |
|  | Ich erinnere mich an die Reise. | I remember the trip. | mich / mir (inline) | rx-s-case-erinnern-1sg-t-an-die-reise |
|  | Du erinnerst dich an den Sommer. | You remember the summer. | mich / mir / dich / dir | rx-s-case-erinnern-2sg-t-an-den-sommer |
|  | Du erinnerst dich an die Reise. | You remember the trip. | dir / dich (inline) | rx-s-case-erinnern-2sg-t-an-die-reise |

### sich freuen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich freue mich auf das Wochenende. | I look forward to the weekend. | mich / mir (inline) | rx-s-case-freuen-1sg-t-auf-das-wochenende |
|  | Ich freue mich auf die Ferien. | I look forward to the holidays. | mir / mich (inline) | rx-s-case-freuen-1sg-t-auf-die-ferien |
|  | Du freust dich auf das Wochenende. | You look forward to the weekend. | dir / dich (inline) | rx-s-case-freuen-2sg-t-auf-das-wochenende |
|  | Du freust dich auf die Ferien. | You look forward to the holidays. | dir / dich (inline) | rx-s-case-freuen-2sg-t-auf-die-ferien |

### sich fühlen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich fühle mich gut. | I feel good. | mich / mir / dich / dir | rx-s-case-fuehlen-1sg-t-gut |
|  | Ich fühle mich müde. | I feel tired. | mich / mir (inline) | rx-s-case-fuehlen-1sg-t-muede |
|  | Du fühlst dich gut. | You feel good. | mich / mir / dich / dir | rx-s-case-fuehlen-2sg-t-gut |
|  | Du fühlst dich müde. | You feel tired. | mich / mir / dich / dir | rx-s-case-fuehlen-2sg-t-muede |

### sich interessieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich interessiere mich für Fußball. | I am interested in football. | mich / mir / dich / dir | rx-s-case-interessieren-1sg-t-fuer-fussball |
|  | Ich interessiere mich für Musik. | I am interested in music. | mich / mir / dich / dir | rx-s-case-interessieren-1sg-t-fuer-musik |
|  | Du interessierst dich für Fußball. | You are interested in football. | mich / mir / dich / dir | rx-s-case-interessieren-2sg-t-fuer-fussball |
|  | Du interessierst dich für Musik. | You are interested in music. | mich / mir / dich / dir | rx-s-case-interessieren-2sg-t-fuer-musik |

### sich kaufen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich kaufe mir ein Auto. | I buy myself a car. | mich / mir / dich / dir | rx-s-case-kaufen-1sg-auto |
|  | Ich kaufe mir einen Kaffee. | I buy myself a coffee. | mich / mir / dich / dir | rx-s-case-kaufen-1sg-kaffee |
|  | Du kaufst dir ein Auto. | You buy yourself a car. | dir / dich (inline) | rx-s-case-kaufen-2sg-auto |
|  | Du kaufst dir ein Buch. | You buy yourself a book. | mich / mir / dich / dir | rx-s-case-kaufen-2sg-buch |
|  | Du kaufst dir einen Kaffee. | You buy yourself a coffee. | mich / mir / dich / dir | rx-s-case-kaufen-2sg-kaffee |

### sich kämmen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich kämme mich. | I comb my hair. | mich / mir (inline) | rx-s-case-kaemmen-1sg |
|  | Ich kämme mir die Haare. | I comb my hair. | mir / mich (inline) | rx-s-case-kaemmen-1sg-haar |
|  | Du kämmst dich. | You comb your hair. | mich / mir / dich / dir | rx-s-case-kaemmen-2sg |
|  | Du kämmst dir die Haare. | You comb your hair. | mich / mir / dich / dir | rx-s-case-kaemmen-2sg-haar |

### sich leisten

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich leiste mir ein Auto. | I can afford a car. | mich / mir / dich / dir | rx-s-case-leisten-1sg-auto |
|  | Ich leiste mir eine Reise. | I can afford a trip. | mich / mir / dich / dir | rx-s-case-leisten-1sg-reise |
|  | Du leistest dir ein Auto. | You can afford a car. | mich / mir / dich / dir | rx-s-case-leisten-2sg-auto |
|  | Du leistest dir eine Reise. | You can afford a trip. | dich / dir (inline) | rx-s-case-leisten-2sg-reise |

### sich merken

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich merke mir die Adresse. | I remember the address. | mich / mir / dich / dir | rx-s-case-merken-1sg-adresse |
|  | Ich merke mir den Namen. | I remember the name. | mich / mir / dich / dir | rx-s-case-merken-1sg-name |
|  | Ich merke mir die Nummer. | I remember the number. | mich / mir / dich / dir | rx-s-case-merken-1sg-nummer |
|  | Du merkst dir die Adresse. | You remember the address. | mich / mir / dich / dir | rx-s-case-merken-2sg-adresse |
|  | Du merkst dir den Namen. | You remember the name. | mich / mir / dich / dir | rx-s-case-merken-2sg-name |

### sich putzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich putze mir die Zähne. | I brush my teeth. | mich / mir / dich / dir | rx-s-case-putzen-1sg-zahn |

### sich rasieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich rasiere mich. | I shave. | mich / mir (inline) | rx-s-case-rasieren-1sg |
|  | Ich rasiere mir die Beine. | I shave my legs. | mich / mir / dich / dir | rx-s-case-rasieren-1sg-bein |
|  | Ich rasiere mir das Gesicht. | I shave my face. | mich / mir / dich / dir | rx-s-case-rasieren-1sg-gesicht |
|  | Du rasierst dich. | You shave. | mich / mir / dich / dir | rx-s-case-rasieren-2sg |
|  | Du rasierst dir die Beine. | You shave your legs. | dir / dich (inline) | rx-s-case-rasieren-2sg-bein |
|  | Du rasierst dir das Gesicht. | You shave your face. | mich / mir / dich / dir | rx-s-case-rasieren-2sg-gesicht |

### sich setzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich setze mich ans Fenster. | I sit down by the window. | mich / mir / dich / dir | rx-s-case-setzen-1sg-t-ans-fenster |
|  | Ich setze mich auf den Stuhl. | I sit down on the chair. | mich / mir / dich / dir | rx-s-case-setzen-1sg-t-auf-den-stuhl |
|  | Du setzt dich ans Fenster. | You sit down by the window. | mich / mir / dich / dir | rx-s-case-setzen-2sg-t-ans-fenster |
|  | Du setzt dich auf den Stuhl. | You sit down on the chair. | mich / mir / dich / dir | rx-s-case-setzen-2sg-t-auf-den-stuhl |

### sich umziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich schnell um. | I get changed quickly. | mich / mir / dich / dir | rx-s-case-umziehen-1sg-t-schnell |
|  | Du ziehst dich schnell um. | You get changed quickly. | dir / dich (inline) | rx-s-case-umziehen-2sg-t-schnell |

### sich verletzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich verletze mich. | I hurt myself. | mich / mir / dich / dir | rx-s-case-verletzen-1sg |
|  | Ich verletze mir den Arm. | I hurt my arm. | mich / mir / dich / dir | rx-s-case-verletzen-1sg-arm |
|  | Ich verletze mir das Knie. | I hurt my knee. | mich / mir / dich / dir | rx-s-case-verletzen-1sg-knie |
|  | Du verletzt dich. | You hurt yourself. | mich / mir / dich / dir | rx-s-case-verletzen-2sg |
|  | Du verletzt dir den Arm. | You hurt your arm. | mich / mir / dich / dir | rx-s-case-verletzen-2sg-arm |
|  | Du verletzt dir das Knie. | You hurt your knee. | mich / mir / dich / dir | rx-s-case-verletzen-2sg-knie |

### sich vorstellen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich stelle mich vor. | I introduce myself. | mich / mir / dich / dir | rx-s-case-vorstellen-1sg |
|  | Ich stelle mir das Haus vor. | I imagine the house. | mich / mir / dich / dir | rx-s-case-vorstellen-1sg-haus |
|  | Ich stelle mir die Stadt vor. | I imagine the city. | mich / mir / dich / dir | rx-s-case-vorstellen-1sg-stadt |
|  | Du stellst dich vor. | You introduce yourself. | mich / mir / dich / dir | rx-s-case-vorstellen-2sg |
|  | Du stellst dir das Haus vor. | You imagine the house. | dir / dich (inline) | rx-s-case-vorstellen-2sg-haus |
|  | Du stellst dir die Stadt vor. | You imagine the city. | mich / mir / dich / dir | rx-s-case-vorstellen-2sg-stadt |

### sich waschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich wasche mir das Gesicht. | I wash my face. | mich / mir / dich / dir | rx-s-case-waschen-1sg-gesicht |
|  | Ich wasche mir die Haare. | I wash my hair. | mich / mir / dich / dir | rx-s-case-waschen-1sg-haar |
|  | Du wäschst dich. | You wash yourself. | mich / mir / dich / dir | rx-s-case-waschen-2sg |
|  | Du wäschst dir das Gesicht. | You wash your face. | mich / mir / dich / dir | rx-s-case-waschen-2sg-gesicht |
|  | Du wäschst dir die Haare. | You wash your hair. | mich / mir / dich / dir | rx-s-case-waschen-2sg-haar |
|  | Du wäschst dir die Hände. | You wash your hands. | mich / mir / dich / dir | rx-s-case-waschen-2sg-hand |

### sich ärgern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ärgere mich über das Wetter. | I get annoyed about the weather. | mich / mir / dich / dir | rx-s-case-aergern-1sg-t-ueber-das-wetter |
|  | Ich ärgere mich über den Lärm. | I get annoyed about the noise. | mich / mir / dich / dir | rx-s-case-aergern-1sg-t-ueber-den-laerm |
|  | Du ärgerst dich über das Wetter. | You get annoyed about the weather. | dir / dich (inline) | rx-s-case-aergern-2sg-t-ueber-das-wetter |
|  | Du ärgerst dich über den Lärm. | You get annoyed about the noise. | mich / mir / dich / dir | rx-s-case-aergern-2sg-t-ueber-den-laerm |

### sich überlegen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich überlege mir die Antwort. | I think about the answer. | mich / mir (inline) | rx-s-case-ueberlegen-1sg-antwort |
|  | Ich überlege mir einen Plan. | I think about a plan. | mich / mir (inline) | rx-s-case-ueberlegen-1sg-plan |
|  | Du überlegst dir die Antwort. | You think about the answer. | mich / mir / dich / dir | rx-s-case-ueberlegen-2sg-antwort |
|  | Du überlegst dir einen Plan. | You think about a plan. | dir / dich (inline) | rx-s-case-ueberlegen-2sg-plan |


## Die richtige Person

persons: 1pl 16, 1sg 13, 2pl 17, 2sg 21, 3pl 14, 3sg 19

### sich abtrocknen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Du trocknest dir die Haare ab. | You dry your hair. | dir / mir / euch / sich | rx-s-person-abtrocknen-2sg-haar |
|  | Sie trocknen sich ab. | They dry themselves off. | mich / uns / sich / dich | rx-s-person-abtrocknen-3pl |
|  | Sie trocknet sich ab. | She dries herself off. | mich / sich (inline) | rx-s-person-abtrocknen-3sg |

### sich ansehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir sehen uns das Bild an. | We look at the picture. | euch / sich / uns / mir | rx-s-person-ansehen-1pl-bild |
|  | Ich sehe mir das Bild an. | I look at the picture. | euch / uns / mir / dir | rx-s-person-ansehen-1sg-bild |
|  | Ihr seht euch das Bild an. | You look at the picture. | dir / euch / uns / mir | rx-s-person-ansehen-2pl-bild |

### sich anziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir ziehen uns die Jacke an. | We put on our jacket. | dir / euch / uns / sich | rx-s-person-anziehen-1pl-jacke |
|  | Ihr zieht euch an. | You get dressed. | dich / euch / sich / mich | rx-s-person-anziehen-2pl |
|  | Sie ziehen sich den Mantel an. | They put on their coat. | dir / sich (inline) | rx-s-person-anziehen-3pl-mantel |
|  | Sie zieht sich die Schuhe an. | She puts on her shoes. | euch / sich / dir / mir | rx-s-person-anziehen-3sg-schuh |

### sich ausziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir ziehen uns aus. | We get undressed. | mich / uns / sich / euch | rx-s-person-ausziehen-1pl |
|  | Wir ziehen uns den Mantel aus. | We take off our coat. | dir / sich / uns / mir | rx-s-person-ausziehen-1pl-mantel |
|  | Ihr zieht euch den Mantel aus. | You take off your coat. | euch / dir / mir / uns | rx-s-person-ausziehen-2pl-mantel |
|  | Sie ziehen sich die Schuhe aus. | They take off their shoes. | mir / dir / sich / uns | rx-s-person-ausziehen-3pl-schuh |

### sich beeilen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich beeile mich heute. | I hurry today. | euch / mich / uns / dich | rx-s-person-beeilen-1sg-t-heute |
|  | Ihr beeilt euch heute. | You hurry today. | euch / uns (inline) | rx-s-person-beeilen-2pl-t-heute |
|  | Ihr beeilt euch jetzt. | You hurry now. | sich / dich / mich / euch | rx-s-person-beeilen-2pl-t-jetzt |

### sich duschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich dusche mich nach dem Sport. | I shower after sport. | mich / dich / uns / sich | rx-s-person-duschen-1sg-t-nach-dem-sport |
|  | Ihr duscht euch nach dem Sport. | You shower after sport. | uns / euch / mich / dich | rx-s-person-duschen-2pl-t-nach-dem-sport |
|  | Sie duscht sich nach dem Sport. | She showers after sport. | dich / sich (inline) | rx-s-person-duschen-3sg-t-nach-dem-sport |

### sich entschuldigen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir entschuldigen uns beim Lehrer. | We apologise to the teacher. | mich / uns (inline) | rx-s-person-entschuldigen-1pl-t-beim-lehrer |
|  | Ich entschuldige mich beim Lehrer. | I apologise to the teacher. | sich / euch / uns / mich | rx-s-person-entschuldigen-1sg-t-beim-lehrer |
|  | Ihr entschuldigt euch bei der Nachbarin. | You apologise to the neighbour. | uns / euch / mich / dich | rx-s-person-entschuldigen-2pl-t-bei-der-nachbarin |
|  | Er entschuldigt sich beim Lehrer. | He apologises to the teacher. | uns / dich / euch / sich | rx-s-person-entschuldigen-3sg-t-beim-lehrer |

### sich erholen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich erhole mich im Urlaub. | I rest on holiday. | dich / euch / mich / sich | rx-s-person-erholen-1sg-t-im-urlaub |
|  | Sie erholt sich am Wochenende. | She rests at the weekend. | sich / dich / euch / uns | rx-s-person-erholen-3sg-t-am-wochenende |
|  | Sie erholt sich im Urlaub. | She rests on holiday. | mich / sich (inline) | rx-s-person-erholen-3sg-t-im-urlaub |

### sich erinnern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir erinnern uns an die Reise. | We remember the trip. | dich / uns (inline) | rx-s-person-erinnern-1pl-t-an-die-reise |
|  | Du erinnerst dich an den Sommer. | You remember the summer. | dich / sich (inline) | rx-s-person-erinnern-2sg-t-an-den-sommer |
|  | Du erinnerst dich an die Reise. | You remember the trip. | dich / sich / euch / uns | rx-s-person-erinnern-2sg-t-an-die-reise |

### sich freuen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir freuen uns auf die Ferien. | We look forward to the holidays. | sich / uns (inline) | rx-s-person-freuen-1pl-t-auf-die-ferien |
|  | Ihr freut euch auf das Wochenende. | You look forward to the weekend. | dich / euch (inline) | rx-s-person-freuen-2pl-t-auf-das-wochenende |

### sich fühlen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Du fühlst dich gut. | You feel good. | sich / dich (inline) | rx-s-person-fuehlen-2sg-t-gut |
|  | Du fühlst dich müde. | You feel tired. | sich / dich (inline) | rx-s-person-fuehlen-2sg-t-muede |
|  | Sie fühlen sich müde. | They feel tired. | sich / uns (inline) | rx-s-person-fuehlen-3pl-t-muede |
|  | Sie fühlt sich müde. | She feels tired. | dich / uns / mich / sich | rx-s-person-fuehlen-3sg-t-muede |

### sich interessieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir interessieren uns für Fußball. | We are interested in football. | sich / dich / uns / euch | rx-s-person-interessieren-1pl-t-fuer-fussball |
|  | Ich interessiere mich für Fußball. | I am interested in football. | uns / mich / euch / dich | rx-s-person-interessieren-1sg-t-fuer-fussball |
|  | Ihr interessiert euch für Fußball. | You are interested in football. | uns / dich / euch / mich | rx-s-person-interessieren-2pl-t-fuer-fussball |
|  | Du interessierst dich für Musik. | You are interested in music. | dich / uns / sich / euch | rx-s-person-interessieren-2sg-t-fuer-musik |

### sich kaufen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir kaufen uns einen Kaffee. | We buy ourselves a coffee. | uns / euch / mir / dir | rx-s-person-kaufen-1pl-kaffee |
|  | Ich kaufe mir ein Buch. | I buy myself a book. | dir / euch / uns / mir | rx-s-person-kaufen-1sg-buch |

### sich kämmen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ihr kämmt euch. | You comb your hair. | sich / euch / mich / uns | rx-s-person-kaemmen-2pl |
|  | Du kämmst dich. | You comb your hair. | uns / dich (inline) | rx-s-person-kaemmen-2sg |

### sich leisten

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Du leistest dir eine Reise. | You can afford a trip. | uns / sich / mir / dir | rx-s-person-leisten-2sg-reise |
|  | Sie leisten sich eine Reise. | They can afford a trip. | uns / dir / mir / sich | rx-s-person-leisten-3pl-reise |
|  | Er leistet sich ein Auto. | He can afford a car. | sich / euch / mir / uns | rx-s-person-leisten-3sg-auto |
|  | Sie leistet sich eine Reise. | She can afford a trip. | sich / mir / dir / euch | rx-s-person-leisten-3sg-reise |

### sich merken

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir merken uns den Namen. | We remember the name. | mir / euch / dir / uns | rx-s-person-merken-1pl-name |
|  | Ich merke mir die Nummer. | I remember the number. | uns / mir / dir / sich | rx-s-person-merken-1sg-nummer |
|  | Du merkst dir die Adresse. | You remember the address. | uns / dir / sich / euch | rx-s-person-merken-2sg-adresse |
|  | Du merkst dir den Namen. | You remember the name. | uns / dir / sich / mir | rx-s-person-merken-2sg-name |
|  | Du merkst dir die Nummer. | You remember the number. | sich / dir (inline) | rx-s-person-merken-2sg-nummer |
|  | Sie merken sich den Namen. | They remember the name. | mir / euch / sich / uns | rx-s-person-merken-3pl-name |
|  | Sie merkt sich die Adresse. | She remembers the address. | dir / sich / mir / uns | rx-s-person-merken-3sg-adresse |
|  | Er merkt sich die Nummer. | He remembers the number. | dir / uns / euch / sich | rx-s-person-merken-3sg-nummer |

### sich putzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich putze mir die Zähne. | I brush my teeth. | sich / euch / mir / uns | rx-s-person-putzen-1sg-zahn |
|  | Du putzt dir die Zähne. | You brush your teeth. | dir / mir (inline) | rx-s-person-putzen-2sg-zahn |
|  | Er putzt sich die Zähne. | He brushes his teeth. | sich / uns (inline) | rx-s-person-putzen-3sg-zahn |

### sich rasieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir rasieren uns. | We shave. | mich / dich / euch / uns | rx-s-person-rasieren-1pl |
|  | Wir rasieren uns das Gesicht. | We shave our face. | uns / dir / mir / sich | rx-s-person-rasieren-1pl-gesicht |
|  | Ihr rasiert euch das Gesicht. | You shave your face. | uns / euch / mir / dir | rx-s-person-rasieren-2pl-gesicht |
|  | Sie rasieren sich. | They shave. | uns / sich (inline) | rx-s-person-rasieren-3pl |
|  | Sie rasiert sich. | She shaves. | mich / sich (inline) | rx-s-person-rasieren-3sg |
|  | Sie rasiert sich die Beine. | She shaves her legs. | uns / sich / mir / euch | rx-s-person-rasieren-3sg-bein |

### sich setzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich setze mich auf den Stuhl. | I sit down on the chair. | euch / sich / mich / dich | rx-s-person-setzen-1sg-t-auf-den-stuhl |
|  | Du setzt dich ans Fenster. | You sit down by the window. | dich / uns / sich / mich | rx-s-person-setzen-2sg-t-ans-fenster |
|  | Du setzt dich auf den Stuhl. | You sit down on the chair. | uns / mich / euch / dich | rx-s-person-setzen-2sg-t-auf-den-stuhl |

### sich treffen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ihr trefft euch im Park. | You meet in the park. | euch / uns / dich / mich | rx-s-person-treffen-2pl-t-im-park |
|  | Sie treffen sich um sieben. | They meet at seven. | euch / sich / dich / uns | rx-s-person-treffen-3pl-t-um-sieben |

### sich umziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich schnell um. | I get changed quickly. | mich / sich / dich / euch | rx-s-person-umziehen-1sg-t-schnell |
|  | Ihr zieht euch schnell um. | You get changed quickly. | mich / euch / dich / sich | rx-s-person-umziehen-2pl-t-schnell |

### sich verletzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich verletze mir den Arm. | I hurt my arm. | dir / mir (inline) | rx-s-person-verletzen-1sg-arm |
|  | Ihr verletzt euch den Arm. | You hurt your arm. | euch / dir / mir / uns | rx-s-person-verletzen-2pl-arm |
|  | Ihr verletzt euch das Knie. | You hurt your knee. | uns / euch (inline) | rx-s-person-verletzen-2pl-knie |
|  | Du verletzt dir den Arm. | You hurt your arm. | sich / mir / euch / dir | rx-s-person-verletzen-2sg-arm |
|  | Sie verletzen sich. | They hurt themselves. | uns / sich / mich / euch | rx-s-person-verletzen-3pl |
|  | Sie verletzt sich das Knie. | She hurts her knee. | uns / sich / dir / euch | rx-s-person-verletzen-3sg-knie |

### sich vorstellen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir stellen uns vor. | We introduce ourselves. | uns / mich (inline) | rx-s-person-vorstellen-1pl |
|  | Wir stellen uns das Haus vor. | We imagine the house. | sich / uns / euch / dir | rx-s-person-vorstellen-1pl-haus |
|  | Du stellst dir das Haus vor. | You imagine the house. | mir / dir / sich / euch | rx-s-person-vorstellen-2sg-haus |
|  | Sie stellen sich vor. | They introduce themselves. | uns / euch / mich / sich | rx-s-person-vorstellen-3pl |
|  | Sie stellen sich das Haus vor. | They imagine the house. | sich / uns / mir / euch | rx-s-person-vorstellen-3pl-haus |

### sich waschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich wasche mir die Hände. | I wash my hands. | dir / euch / mir / sich | rx-s-person-waschen-1sg-hand |
|  | Ihr wascht euch das Gesicht. | You wash your face. | euch / sich / dir / uns | rx-s-person-waschen-2pl-gesicht |
|  | Du wäschst dich. | You wash yourself. | dich / sich / euch / uns | rx-s-person-waschen-2sg |
|  | Du wäschst dir das Gesicht. | You wash your face. | sich / uns / dir / euch | rx-s-person-waschen-2sg-gesicht |
|  | Du wäschst dir die Haare. | You wash your hair. | mir / dir / sich / euch | rx-s-person-waschen-2sg-haar |
|  | Sie waschen sich. | They wash themselves. | sich / euch / dich / mich | rx-s-person-waschen-3pl |
|  | Sie waschen sich das Gesicht. | They wash their face. | uns / mir / sich / euch | rx-s-person-waschen-3pl-gesicht |
|  | Er wäscht sich. | He washes himself. | dich / sich / mich / euch | rx-s-person-waschen-3sg |
|  | Sie wäscht sich das Gesicht. | She washes her face. | sich / mir / euch / uns | rx-s-person-waschen-3sg-gesicht |
|  | Er wäscht sich die Haare. | He washes his hair. | sich / uns / mir / dir | rx-s-person-waschen-3sg-haar |
|  | Er wäscht sich die Hände. | He washes his hands. | dir / uns / sich / mir | rx-s-person-waschen-3sg-hand |

### sich ärgern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir ärgern uns über den Lärm. | We get annoyed about the noise. | uns / mich (inline) | rx-s-person-aergern-1pl-t-ueber-den-laerm |
|  | Du ärgerst dich über das Wetter. | You get annoyed about the weather. | dich / mich (inline) | rx-s-person-aergern-2sg-t-ueber-das-wetter |

### sich überlegen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir überlegen uns die Antwort. | We think about the answer. | dir / uns (inline) | rx-s-person-ueberlegen-1pl-antwort |
|  | Ihr überlegt euch einen Plan. | You think about a plan. | dir / euch / uns / mir | rx-s-person-ueberlegen-2pl-plan |
|  | Du überlegst dir einen Plan. | You think about a plan. | mir / euch / dir / sich | rx-s-person-ueberlegen-2sg-plan |
|  | Sie überlegen sich die Antwort. | They think about the answer. | euch / mir / sich / dir | rx-s-person-ueberlegen-3pl-antwort |

