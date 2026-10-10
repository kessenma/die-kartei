# Reflexive items from the planner: review sheet

Seed 7. 119 Akkusativ oder Dativ?, 100 Die richtige Person; 219 pass the gate, 219 in `candidates.json`.

The German comes from the verb table, never from a model. Read each row: is it natural German a teacher would put on a worksheet, and is the English twin right? Mark `reads_right` (✓/✗) and a `note` in `review.csv`. A ✗ names a table row to fix (the verb's forms, its objects, a tail, the English pattern); then the pack is regenerated with the same seed.

| focus | items | pass | candidates | Akk | Dat | inline |
|---|---:|---:|---:|---:|---:|---:|
| Akkusativ oder Dativ? | 119 | 119 | 119 | 60 | 59 | 29 |
| Die richtige Person | 100 | 100 | 100 | 51 | 49 | 25 |

## Akkusativ oder Dativ?

persons: 1sg 59, 2sg 60

### sich abtrocknen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich trockne mich ab. | I dry myself off. | mir / mich (inline) | rx-s-case-abtrocknen-1sg |
|  | Ich trockne mir die Haare ab. | I dry my hair. | mich / mir / dich / dir | rx-s-case-abtrocknen-1sg-haar |
|  | Ich trockne mir die Hände ab. | I dry my hands. | mich / mir / dich / dir | rx-s-case-abtrocknen-1sg-hand |
|  | Du trocknest dich ab. | You dry yourself off. | mich / mir / dich / dir | rx-s-case-abtrocknen-2sg |
|  | Du trocknest dir die Haare ab. | You dry your hair. | mich / mir / dich / dir | rx-s-case-abtrocknen-2sg-haar |
|  | Du trocknest dir die Hände ab. | You dry your hands. | dich / dir (inline) | rx-s-case-abtrocknen-2sg-hand |

### sich ansehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich sehe mir das Bild an. | I look at the picture. | mich / mir / dich / dir | rx-s-case-ansehen-1sg-bild |
|  | Ich sehe mir das Foto an. | I look at the photo. | mich / mir / dich / dir | rx-s-case-ansehen-1sg-foto |
|  | Du siehst dir das Bild an. | You look at the picture. | dir / dich (inline) | rx-s-case-ansehen-2sg-bild |
|  | Du siehst dir das Foto an. | You look at the photo. | mich / mir / dich / dir | rx-s-case-ansehen-2sg-foto |

### sich anziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich an. | I get dressed. | mich / mir / dich / dir | rx-s-case-anziehen-1sg |
|  | Ich ziehe mir den Mantel an. | I put on my coat. | mich / mir / dich / dir | rx-s-case-anziehen-1sg-mantel |
|  | Ich ziehe mir die Schuhe an. | I put on my shoes. | mich / mir / dich / dir | rx-s-case-anziehen-1sg-schuh |
|  | Du ziehst dich an. | You get dressed. | dir / dich (inline) | rx-s-case-anziehen-2sg |
|  | Du ziehst dir die Jacke an. | You put on your jacket. | mich / mir / dich / dir | rx-s-case-anziehen-2sg-jacke |
|  | Du ziehst dir den Mantel an. | You put on your coat. | dich / dir (inline) | rx-s-case-anziehen-2sg-mantel |
|  | Du ziehst dir die Schuhe an. | You put on your shoes. | dich / dir (inline) | rx-s-case-anziehen-2sg-schuh |

### sich ausziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich aus. | I get undressed. | mich / mir / dich / dir | rx-s-case-ausziehen-1sg |
|  | Ich ziehe mir die Jacke aus. | I take off my jacket. | mich / mir / dich / dir | rx-s-case-ausziehen-1sg-jacke |
|  | Ich ziehe mir den Mantel aus. | I take off my coat. | mich / mir (inline) | rx-s-case-ausziehen-1sg-mantel |
|  | Ich ziehe mir die Schuhe aus. | I take off my shoes. | mich / mir / dich / dir | rx-s-case-ausziehen-1sg-schuh |
|  | Du ziehst dich aus. | You get undressed. | mich / mir / dich / dir | rx-s-case-ausziehen-2sg |
|  | Du ziehst dir die Jacke aus. | You take off your jacket. | mich / mir / dich / dir | rx-s-case-ausziehen-2sg-jacke |
|  | Du ziehst dir den Mantel aus. | You take off your coat. | dich / dir (inline) | rx-s-case-ausziehen-2sg-mantel |
|  | Du ziehst dir die Schuhe aus. | You take off your shoes. | mich / mir / dich / dir | rx-s-case-ausziehen-2sg-schuh |

### sich beeilen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich beeile mich heute. | I hurry today. | mich / mir / dich / dir | rx-s-case-beeilen-1sg-t-heute |
|  | Ich beeile mich jetzt. | I hurry now. | mich / mir / dich / dir | rx-s-case-beeilen-1sg-t-jetzt |
|  | Du beeilst dich heute. | You hurry today. | mich / mir / dich / dir | rx-s-case-beeilen-2sg-t-heute |
|  | Du beeilst dich jetzt. | You hurry now. | mich / mir / dich / dir | rx-s-case-beeilen-2sg-t-jetzt |

### sich duschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich dusche mich am Morgen. | I shower in the morning. | mich / mir / dich / dir | rx-s-case-duschen-1sg-t-am-morgen |
|  | Ich dusche mich nach dem Sport. | I shower after sport. | mich / mir / dich / dir | rx-s-case-duschen-1sg-t-nach-dem-sport |
|  | Du duschst dich am Morgen. | You shower in the morning. | mich / mir / dich / dir | rx-s-case-duschen-2sg-t-am-morgen |
|  | Du duschst dich nach dem Sport. | You shower after sport. | mich / mir / dich / dir | rx-s-case-duschen-2sg-t-nach-dem-sport |

### sich entschuldigen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich entschuldige mich bei der Nachbarin. | I apologise to the neighbour. | mich / mir / dich / dir | rx-s-case-entschuldigen-1sg-t-bei-der-nachbarin |
|  | Ich entschuldige mich beim Lehrer. | I apologise to the teacher. | mich / mir / dich / dir | rx-s-case-entschuldigen-1sg-t-beim-lehrer |
|  | Du entschuldigst dich bei der Nachbarin. | You apologise to the neighbour. | mich / mir / dich / dir | rx-s-case-entschuldigen-2sg-t-bei-der-nachbarin |
|  | Du entschuldigst dich beim Lehrer. | You apologise to the teacher. | mich / mir / dich / dir | rx-s-case-entschuldigen-2sg-t-beim-lehrer |

### sich erholen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich erhole mich am Wochenende. | I rest at the weekend. | mich / mir (inline) | rx-s-case-erholen-1sg-t-am-wochenende |
|  | Ich erhole mich im Urlaub. | I rest on holiday. | mich / mir (inline) | rx-s-case-erholen-1sg-t-im-urlaub |
|  | Du erholst dich im Urlaub. | You rest on holiday. | mich / mir / dich / dir | rx-s-case-erholen-2sg-t-im-urlaub |

### sich erinnern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich erinnere mich an den Sommer. | I remember the summer. | mich / mir / dich / dir | rx-s-case-erinnern-1sg-t-an-den-sommer |
|  | Ich erinnere mich an die Reise. | I remember the trip. | mich / mir / dich / dir | rx-s-case-erinnern-1sg-t-an-die-reise |
|  | Du erinnerst dich an den Sommer. | You remember the summer. | mich / mir / dich / dir | rx-s-case-erinnern-2sg-t-an-den-sommer |
|  | Du erinnerst dich an die Reise. | You remember the trip. | mich / mir / dich / dir | rx-s-case-erinnern-2sg-t-an-die-reise |

### sich freuen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich freue mich auf das Wochenende. | I look forward to the weekend. | mich / mir / dich / dir | rx-s-case-freuen-1sg-t-auf-das-wochenende |
|  | Ich freue mich auf die Ferien. | I look forward to the holidays. | mich / mir / dich / dir | rx-s-case-freuen-1sg-t-auf-die-ferien |
|  | Du freust dich auf das Wochenende. | You look forward to the weekend. | mich / mir / dich / dir | rx-s-case-freuen-2sg-t-auf-das-wochenende |
|  | Du freust dich auf die Ferien. | You look forward to the holidays. | mich / mir / dich / dir | rx-s-case-freuen-2sg-t-auf-die-ferien |

### sich fühlen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich fühle mich gut. | I feel good. | mich / mir / dich / dir | rx-s-case-fuehlen-1sg-t-gut |
|  | Ich fühle mich müde. | I feel tired. | mir / mich (inline) | rx-s-case-fuehlen-1sg-t-muede |
|  | Du fühlst dich gut. | You feel good. | mich / mir / dich / dir | rx-s-case-fuehlen-2sg-t-gut |
|  | Du fühlst dich müde. | You feel tired. | mich / mir / dich / dir | rx-s-case-fuehlen-2sg-t-muede |

### sich interessieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich interessiere mich für Fußball. | I am interested in football. | mich / mir / dich / dir | rx-s-case-interessieren-1sg-t-fuer-fussball |
|  | Ich interessiere mich für Musik. | I am interested in music. | mich / mir / dich / dir | rx-s-case-interessieren-1sg-t-fuer-musik |
|  | Du interessierst dich für Fußball. | You are interested in football. | dich / dir (inline) | rx-s-case-interessieren-2sg-t-fuer-fussball |
|  | Du interessierst dich für Musik. | You are interested in music. | mich / mir / dich / dir | rx-s-case-interessieren-2sg-t-fuer-musik |

### sich kaufen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich kaufe mir ein Auto. | I buy myself a car. | mich / mir / dich / dir | rx-s-case-kaufen-1sg-auto |
|  | Ich kaufe mir einen Kaffee. | I buy myself a coffee. | mich / mir / dich / dir | rx-s-case-kaufen-1sg-kaffee |
|  | Du kaufst dir ein Auto. | You buy yourself a car. | mich / mir / dich / dir | rx-s-case-kaufen-2sg-auto |
|  | Du kaufst dir ein Buch. | You buy yourself a book. | mich / mir / dich / dir | rx-s-case-kaufen-2sg-buch |
|  | Du kaufst dir einen Kaffee. | You buy yourself a coffee. | mich / mir / dich / dir | rx-s-case-kaufen-2sg-kaffee |

### sich kämmen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich kämme mich. | I comb my hair. | mich / mir (inline) | rx-s-case-kaemmen-1sg |
|  | Ich kämme mir die Haare. | I comb my hair. | mich / mir (inline) | rx-s-case-kaemmen-1sg-haar |
|  | Du kämmst dich. | You comb your hair. | mich / mir / dich / dir | rx-s-case-kaemmen-2sg |
|  | Du kämmst dir die Haare. | You comb your hair. | dich / dir (inline) | rx-s-case-kaemmen-2sg-haar |

### sich leisten

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich leiste mir ein Auto. | I can afford a car. | mich / mir / dich / dir | rx-s-case-leisten-1sg-auto |
|  | Ich leiste mir eine Reise. | I can afford a trip. | mich / mir / dich / dir | rx-s-case-leisten-1sg-reise |
|  | Du leistest dir ein Auto. | You can afford a car. | mich / mir / dich / dir | rx-s-case-leisten-2sg-auto |
|  | Du leistest dir eine Reise. | You can afford a trip. | mich / mir / dich / dir | rx-s-case-leisten-2sg-reise |

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
|  | Ich putze mir die Nase. | I brush my nose. | mich / mir / dich / dir | rx-s-case-putzen-1sg-nase |
|  | Ich putze mir die Zähne. | I brush my teeth. | mich / mir / dich / dir | rx-s-case-putzen-1sg-zahn |
|  | Du putzt dir die Nase. | You brush your nose. | mich / mir / dich / dir | rx-s-case-putzen-2sg-nase |

### sich rasieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich rasiere mich. | I shave. | mich / mir / dich / dir | rx-s-case-rasieren-1sg |
|  | Ich rasiere mir die Beine. | I shave my legs. | mich / mir / dich / dir | rx-s-case-rasieren-1sg-bein |
|  | Ich rasiere mir das Gesicht. | I shave my face. | mich / mir / dich / dir | rx-s-case-rasieren-1sg-gesicht |
|  | Du rasierst dich. | You shave. | dich / dir (inline) | rx-s-case-rasieren-2sg |
|  | Du rasierst dir die Beine. | You shave your legs. | dich / dir (inline) | rx-s-case-rasieren-2sg-bein |
|  | Du rasierst dir das Gesicht. | You shave your face. | dich / dir (inline) | rx-s-case-rasieren-2sg-gesicht |

### sich setzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich setze mich ans Fenster. | I sit down by the window. | mich / mir / dich / dir | rx-s-case-setzen-1sg-t-ans-fenster |
|  | Ich setze mich auf den Stuhl. | I sit down on the chair. | mir / mich (inline) | rx-s-case-setzen-1sg-t-auf-den-stuhl |
|  | Du setzt dich ans Fenster. | You sit down by the window. | dir / dich (inline) | rx-s-case-setzen-2sg-t-ans-fenster |
|  | Du setzt dich auf den Stuhl. | You sit down on the chair. | mich / mir / dich / dir | rx-s-case-setzen-2sg-t-auf-den-stuhl |

### sich treffen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich treffe mich im Park. | I meet in the park. | mir / mich (inline) | rx-s-case-treffen-1sg-t-im-park |
|  | Ich treffe mich um sieben. | I meet at seven. | mich / mir (inline) | rx-s-case-treffen-1sg-t-um-sieben |
|  | Du triffst dich im Park. | You meet in the park. | mich / mir / dich / dir | rx-s-case-treffen-2sg-t-im-park |
|  | Du triffst dich um sieben. | You meet at seven. | mich / mir / dich / dir | rx-s-case-treffen-2sg-t-um-sieben |

### sich umziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich schnell um. | I get changed quickly. | mich / mir / dich / dir | rx-s-case-umziehen-1sg-t-schnell |
|  | Du ziehst dich schnell um. | You get changed quickly. | mich / mir / dich / dir | rx-s-case-umziehen-2sg-t-schnell |

### sich verletzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich verletze mich. | I hurt myself. | mir / mich (inline) | rx-s-case-verletzen-1sg |
|  | Ich verletze mir den Arm. | I hurt my arm. | mich / mir / dich / dir | rx-s-case-verletzen-1sg-arm |
|  | Ich verletze mir das Knie. | I hurt my knee. | mir / mich (inline) | rx-s-case-verletzen-1sg-knie |
|  | Du verletzt dich. | You hurt yourself. | mich / mir / dich / dir | rx-s-case-verletzen-2sg |
|  | Du verletzt dir den Arm. | You hurt your arm. | dich / dir (inline) | rx-s-case-verletzen-2sg-arm |
|  | Du verletzt dir das Knie. | You hurt your knee. | mich / mir / dich / dir | rx-s-case-verletzen-2sg-knie |

### sich vorstellen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich stelle mich vor. | I introduce myself. | mich / mir / dich / dir | rx-s-case-vorstellen-1sg |
|  | Ich stelle mir das Haus vor. | I imagine the house. | mich / mir / dich / dir | rx-s-case-vorstellen-1sg-haus |
|  | Ich stelle mir die Stadt vor. | I imagine the city. | mich / mir / dich / dir | rx-s-case-vorstellen-1sg-stadt |
|  | Du stellst dich vor. | You introduce yourself. | mich / mir / dich / dir | rx-s-case-vorstellen-2sg |
|  | Du stellst dir das Haus vor. | You imagine the house. | mich / mir / dich / dir | rx-s-case-vorstellen-2sg-haus |
|  | Du stellst dir die Stadt vor. | You imagine the city. | mich / mir / dich / dir | rx-s-case-vorstellen-2sg-stadt |

### sich waschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich wasche mir das Gesicht. | I wash my face. | mich / mir / dich / dir | rx-s-case-waschen-1sg-gesicht |
|  | Ich wasche mir die Haare. | I wash my hair. | mich / mir / dich / dir | rx-s-case-waschen-1sg-haar |
|  | Du wäschst dich. | You wash yourself. | mich / mir / dich / dir | rx-s-case-waschen-2sg |
|  | Du wäschst dir das Gesicht. | You wash your face. | mich / mir / dich / dir | rx-s-case-waschen-2sg-gesicht |
|  | Du wäschst dir die Haare. | You wash your hair. | dich / dir (inline) | rx-s-case-waschen-2sg-haar |
|  | Du wäschst dir die Hände. | You wash your hands. | mich / mir / dich / dir | rx-s-case-waschen-2sg-hand |

### sich ärgern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ärgere mich über das Wetter. | I get annoyed about the weather. | mich / mir / dich / dir | rx-s-case-aergern-1sg-t-ueber-das-wetter |
|  | Ich ärgere mich über den Lärm. | I get annoyed about the noise. | mich / mir (inline) | rx-s-case-aergern-1sg-t-ueber-den-laerm |
|  | Du ärgerst dich über das Wetter. | You get annoyed about the weather. | mich / mir / dich / dir | rx-s-case-aergern-2sg-t-ueber-das-wetter |
|  | Du ärgerst dich über den Lärm. | You get annoyed about the noise. | mich / mir / dich / dir | rx-s-case-aergern-2sg-t-ueber-den-laerm |

### sich überlegen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich überlege mir die Antwort. | I think about the answer. | mir / mich (inline) | rx-s-case-ueberlegen-1sg-antwort |
|  | Ich überlege mir einen Plan. | I think about a plan. | mich / mir / dich / dir | rx-s-case-ueberlegen-1sg-plan |
|  | Du überlegst dir die Antwort. | You think about the answer. | mich / mir / dich / dir | rx-s-case-ueberlegen-2sg-antwort |
|  | Du überlegst dir einen Plan. | You think about a plan. | dir / dich (inline) | rx-s-case-ueberlegen-2sg-plan |


## Die richtige Person

persons: 1pl 13, 1sg 18, 2pl 18, 2sg 13, 3pl 13, 3sg 25

### sich abtrocknen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir trocknen uns ab. | We dry ourselves off. | dich / uns (inline) | rx-s-person-abtrocknen-1pl |
|  | Du trocknest dich ab. | You dry yourself off. | euch / dich / mich / uns | rx-s-person-abtrocknen-2sg |

### sich ansehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir sehen uns das Bild an. | We look at the picture. | euch / dir / sich / uns | rx-s-person-ansehen-1pl-bild |
|  | Ich sehe mir das Bild an. | I look at the picture. | mir / uns / euch / sich | rx-s-person-ansehen-1sg-bild |
|  | Ihr seht euch das Bild an. | You look at the picture. | sich / uns / mir / euch | rx-s-person-ansehen-2pl-bild |
|  | Ihr seht euch das Foto an. | You look at the photo. | euch / uns (inline) | rx-s-person-ansehen-2pl-foto |

### sich anziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich ziehe mich an. | I get dressed. | mich / uns (inline) | rx-s-person-anziehen-1sg |
|  | Ihr zieht euch den Mantel an. | You put on your coat. | uns / sich / dir / euch | rx-s-person-anziehen-2pl-mantel |
|  | Sie zieht sich die Schuhe an. | She puts on her shoes. | dir / euch / sich / mir | rx-s-person-anziehen-3sg-schuh |

### sich ausziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir ziehen uns den Mantel aus. | We take off our coat. | euch / sich / mir / uns | rx-s-person-ausziehen-1pl-mantel |
|  | Ihr zieht euch aus. | You get undressed. | mich / euch / uns / sich | rx-s-person-ausziehen-2pl |
|  | Ihr zieht euch die Jacke aus. | You take off your jacket. | sich / dir / euch / uns | rx-s-person-ausziehen-2pl-jacke |
|  | Ihr zieht euch den Mantel aus. | You take off your coat. | sich / euch / dir / mir | rx-s-person-ausziehen-2pl-mantel |
|  | Sie ziehen sich den Mantel aus. | They take off their coat. | sich / uns (inline) | rx-s-person-ausziehen-3pl-mantel |
|  | Sie zieht sich die Jacke aus. | She takes off her jacket. | sich / dir / euch / uns | rx-s-person-ausziehen-3sg-jacke |
|  | Sie zieht sich die Schuhe aus. | She takes off her shoes. | uns / sich / mir / dir | rx-s-person-ausziehen-3sg-schuh |

### sich beeilen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich beeile mich jetzt. | I hurry now. | mich / dich / euch / sich | rx-s-person-beeilen-1sg-t-jetzt |
|  | Sie beeilen sich heute. | They hurry today. | euch / sich / dich / uns | rx-s-person-beeilen-3pl-t-heute |

### sich duschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir duschen uns am Morgen. | We shower in the morning. | uns / dich / mich / sich | rx-s-person-duschen-1pl-t-am-morgen |
|  | Ich dusche mich am Morgen. | I shower in the morning. | uns / mich (inline) | rx-s-person-duschen-1sg-t-am-morgen |
|  | Du duschst dich am Morgen. | You shower in the morning. | sich / mich / uns / dich | rx-s-person-duschen-2sg-t-am-morgen |
|  | Er duscht sich nach dem Sport. | He showers after sport. | mich / uns / sich / euch | rx-s-person-duschen-3sg-t-nach-dem-sport |

### sich entschuldigen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich entschuldige mich bei der Nachbarin. | I apologise to the neighbour. | sich / dich / mich / uns | rx-s-person-entschuldigen-1sg-t-bei-der-nachbarin |
|  | Ihr entschuldigt euch beim Lehrer. | You apologise to the teacher. | euch / dich / sich / mich | rx-s-person-entschuldigen-2pl-t-beim-lehrer |
|  | Du entschuldigst dich bei der Nachbarin. | You apologise to the neighbour. | euch / dich (inline) | rx-s-person-entschuldigen-2sg-t-bei-der-nachbarin |
|  | Du entschuldigst dich beim Lehrer. | You apologise to the teacher. | uns / dich (inline) | rx-s-person-entschuldigen-2sg-t-beim-lehrer |
|  | Sie entschuldigt sich beim Lehrer. | She apologises to the teacher. | sich / dich / euch / mich | rx-s-person-entschuldigen-3sg-t-beim-lehrer |

### sich erholen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir erholen uns im Urlaub. | We rest on holiday. | euch / uns / dich / mich | rx-s-person-erholen-1pl-t-im-urlaub |
|  | Ich erhole mich am Wochenende. | I rest at the weekend. | dich / uns / mich / sich | rx-s-person-erholen-1sg-t-am-wochenende |
|  | Ihr erholt euch am Wochenende. | You rest at the weekend. | dich / uns / sich / euch | rx-s-person-erholen-2pl-t-am-wochenende |
|  | Du erholst dich im Urlaub. | You rest on holiday. | dich / uns / euch / sich | rx-s-person-erholen-2sg-t-im-urlaub |
|  | Sie erholt sich am Wochenende. | She rests at the weekend. | euch / sich / dich / mich | rx-s-person-erholen-3sg-t-am-wochenende |

### sich erinnern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Sie erinnert sich an den Sommer. | She remembers the summer. | sich / euch / mich / uns | rx-s-person-erinnern-3sg-t-an-den-sommer |
|  | Sie erinnert sich an die Reise. | She remembers the trip. | dich / euch / uns / sich | rx-s-person-erinnern-3sg-t-an-die-reise |

### sich freuen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Sie freuen sich auf das Wochenende. | They look forward to the weekend. | uns / dich / euch / sich | rx-s-person-freuen-3pl-t-auf-das-wochenende |
|  | Sie freut sich auf die Ferien. | She looks forward to the holidays. | euch / sich / mich / uns | rx-s-person-freuen-3sg-t-auf-die-ferien |

### sich fühlen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir fühlen uns müde. | We feel tired. | mich / uns (inline) | rx-s-person-fuehlen-1pl-t-muede |
|  | Ich fühle mich müde. | I feel tired. | uns / mich / euch / dich | rx-s-person-fuehlen-1sg-t-muede |
|  | Ihr fühlt euch gut. | You feel good. | euch / uns (inline) | rx-s-person-fuehlen-2pl-t-gut |
|  | Ihr fühlt euch müde. | You feel tired. | euch / sich / mich / uns | rx-s-person-fuehlen-2pl-t-muede |
|  | Sie fühlen sich gut. | They feel good. | uns / sich / mich / dich | rx-s-person-fuehlen-3pl-t-gut |
|  | Er fühlt sich müde. | He feels tired. | uns / sich / dich / mich | rx-s-person-fuehlen-3sg-t-muede |

### sich interessieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir interessieren uns für Musik. | We are interested in music. | uns / mich / sich / dich | rx-s-person-interessieren-1pl-t-fuer-musik |
|  | Ich interessiere mich für Musik. | I am interested in music. | euch / sich / mich / uns | rx-s-person-interessieren-1sg-t-fuer-musik |

### sich kaufen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir kaufen uns ein Buch. | We buy ourselves a book. | mir / sich / uns / euch | rx-s-person-kaufen-1pl-buch |
|  | Sie kaufen sich einen Kaffee. | They buy themselves a coffee. | sich / uns (inline) | rx-s-person-kaufen-3pl-kaffee |

### sich kämmen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich kämme mir die Haare. | I comb my hair. | euch / sich / uns / mir | rx-s-person-kaemmen-1sg-haar |
|  | Du kämmst dich. | You comb your hair. | euch / uns / mich / dich | rx-s-person-kaemmen-2sg |

### sich leisten

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir leisten uns ein Auto. | We can afford a car. | euch / dir / uns / sich | rx-s-person-leisten-1pl-auto |
|  | Sie leistet sich ein Auto. | She can afford a car. | uns / sich (inline) | rx-s-person-leisten-3sg-auto |

### sich merken

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir merken uns den Namen. | We remember the name. | mir / euch / sich / uns | rx-s-person-merken-1pl-name |
|  | Du merkst dir die Adresse. | You remember the address. | uns / mir / sich / dir | rx-s-person-merken-2sg-adresse |
|  | Du merkst dir den Namen. | You remember the name. | uns / dir / mir / sich | rx-s-person-merken-2sg-name |
|  | Du merkst dir die Nummer. | You remember the number. | dir / euch (inline) | rx-s-person-merken-2sg-nummer |
|  | Sie merken sich die Nummer. | They remember the number. | sich / mir (inline) | rx-s-person-merken-3pl-nummer |
|  | Er merkt sich die Adresse. | He remembers the address. | uns / euch / dir / sich | rx-s-person-merken-3sg-adresse |

### sich putzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Du putzt dir die Nase. | You brush your nose. | sich / uns / euch / dir | rx-s-person-putzen-2sg-nase |
|  | Du putzt dir die Zähne. | You brush your teeth. | uns / dir / euch / sich | rx-s-person-putzen-2sg-zahn |
|  | Sie putzen sich die Nase. | They brush their nose. | euch / sich / dir / uns | rx-s-person-putzen-3pl-nase |
|  | Er putzt sich die Zähne. | He brushes his teeth. | sich / dir / euch / uns | rx-s-person-putzen-3sg-zahn |

### sich rasieren

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich rasiere mich. | I shave. | mich / sich (inline) | rx-s-person-rasieren-1sg |
|  | Ich rasiere mir die Beine. | I shave my legs. | sich / euch / dir / mir | rx-s-person-rasieren-1sg-bein |
|  | Ihr rasiert euch. | You shave. | euch / dich (inline) | rx-s-person-rasieren-2pl |
|  | Ihr rasiert euch das Gesicht. | You shave your face. | sich / euch / mir / dir | rx-s-person-rasieren-2pl-gesicht |
|  | Sie rasiert sich die Beine. | She shaves her legs. | sich / dir (inline) | rx-s-person-rasieren-3sg-bein |
|  | Sie rasiert sich das Gesicht. | She shaves her face. | dir / sich / mir / euch | rx-s-person-rasieren-3sg-gesicht |

### sich setzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Du setzt dich ans Fenster. | You sit down by the window. | dich / sich / euch / uns | rx-s-person-setzen-2sg-t-ans-fenster |
|  | Er setzt sich ans Fenster. | He sits down by the window. | mich / sich (inline) | rx-s-person-setzen-3sg-t-ans-fenster |
|  | Er setzt sich auf den Stuhl. | He sits down on the chair. | sich / dich (inline) | rx-s-person-setzen-3sg-t-auf-den-stuhl |

### sich treffen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich treffe mich um sieben. | I meet at seven. | sich / dich / mich / uns | rx-s-person-treffen-1sg-t-um-sieben |
|  | Sie trifft sich um sieben. | She meets at seven. | mich / dich / sich / euch | rx-s-person-treffen-3sg-t-um-sieben |

### sich umziehen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir ziehen uns schnell um. | We get changed quickly. | uns / sich / dich / mich | rx-s-person-umziehen-1pl-t-schnell |
|  | Ich ziehe mich schnell um. | I get changed quickly. | dich / mich / euch / sich | rx-s-person-umziehen-1sg-t-schnell |

### sich verletzen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich verletze mir den Arm. | I hurt my arm. | euch / dir / mir / uns | rx-s-person-verletzen-1sg-arm |
|  | Ihr verletzt euch. | You hurt yourselves. | sich / mich / euch / uns | rx-s-person-verletzen-2pl |
|  | Sie verletzt sich. | She hurts herself. | uns / dich / sich / mich | rx-s-person-verletzen-3sg |

### sich vorstellen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir stellen uns die Stadt vor. | We imagine the city. | uns / sich (inline) | rx-s-person-vorstellen-1pl-stadt |
|  | Ich stelle mir die Stadt vor. | I imagine the city. | dir / mir (inline) | rx-s-person-vorstellen-1sg-stadt |
|  | Ihr stellt euch vor. | You introduce yourselves. | mich / dich / euch / sich | rx-s-person-vorstellen-2pl |
|  | Ihr stellt euch die Stadt vor. | You imagine the city. | uns / euch (inline) | rx-s-person-vorstellen-2pl-stadt |
|  | Sie stellen sich vor. | They introduce themselves. | mich / euch / uns / sich | rx-s-person-vorstellen-3pl |
|  | Sie stellen sich die Stadt vor. | They imagine the city. | uns / sich / euch / mir | rx-s-person-vorstellen-3pl-stadt |
|  | Sie stellt sich das Haus vor. | She imagines the house. | mir / sich (inline) | rx-s-person-vorstellen-3sg-haus |
|  | Sie stellt sich die Stadt vor. | She imagines the city. | euch / uns / sich / dir | rx-s-person-vorstellen-3sg-stadt |

### sich waschen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Ich wasche mich. | I wash myself. | mich / sich (inline) | rx-s-person-waschen-1sg |
|  | Ich wasche mir die Hände. | I wash my hands. | euch / uns / mir / dir | rx-s-person-waschen-1sg-hand |
|  | Ihr wascht euch das Gesicht. | You wash your face. | mir / euch / uns / dir | rx-s-person-waschen-2pl-gesicht |
|  | Ihr wascht euch die Hände. | You wash your hands. | euch / uns / mir / sich | rx-s-person-waschen-2pl-hand |
|  | Sie waschen sich. | They wash themselves. | sich / euch / mich / dich | rx-s-person-waschen-3pl |
|  | Sie waschen sich das Gesicht. | They wash their face. | uns / sich / dir / euch | rx-s-person-waschen-3pl-gesicht |
|  | Sie waschen sich die Hände. | They wash their hands. | dir / sich / mir / uns | rx-s-person-waschen-3pl-hand |
|  | Er wäscht sich. | He washes himself. | sich / dich / euch / mich | rx-s-person-waschen-3sg |
|  | Er wäscht sich das Gesicht. | He washes his face. | dir / sich (inline) | rx-s-person-waschen-3sg-gesicht |

### sich ärgern

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Du ärgerst dich über den Lärm. | You get annoyed about the noise. | mich / sich / dich / uns | rx-s-person-aergern-2sg-t-ueber-den-laerm |
|  | Sie ärgert sich über das Wetter. | She gets annoyed about the weather. | mich / dich / euch / sich | rx-s-person-aergern-3sg-t-ueber-das-wetter |

### sich überlegen

| ✓/✗ | German | English | options | id |
|---|---|---|---|---|
|  | Wir überlegen uns einen Plan. | We think about a plan. | sich / uns / euch / dir | rx-s-person-ueberlegen-1pl-plan |
|  | Ich überlege mir die Antwort. | I think about the answer. | uns / sich / dir / mir | rx-s-person-ueberlegen-1sg-antwort |
|  | Ihr überlegt euch die Antwort. | You think about the answer. | sich / euch / dir / mir | rx-s-person-ueberlegen-2pl-antwort |
|  | Sie überlegen sich einen Plan. | They think about a plan. | sich / uns (inline) | rx-s-person-ueberlegen-3pl-plan |
|  | Er überlegt sich die Antwort. | He thinks about the answer. | dir / euch / sich / uns | rx-s-person-ueberlegen-3sg-antwort |

