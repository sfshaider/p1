#!/usr/local/bin/perl

package language;
require Exporter;
use strict;

#
#  IF YOU ADD A CONSTANT YOU MUST EXPORT IT ON THE EXPORT_OK LINE.
#
#  TO IMPORT DO use constants qw(list of vars you want to import)
#

our @ISA	= qw("Exporter");
our @EXPORT_OK  = qw(%lang_titles %billpay_titles %receipt_titles);


  %language::lang_titles = (
    "name"     => ["Name",       "Nombre",       "Nom", "Naam"],
    "fname"    => ["First Name", "Primer Nombre", "Pr&#233;nom", "Voornaam"],
    "lname"    => ["Last Name",  "Apellido",  "Dernier nom", "Achternaam"],
    "company"  => ["Company",    "Compa&#164;&#237;a",    "Soci&#233;t&#233;", "Bedrijf"],
    "card_address1" => ["Billing Address",   "Direcci&#243;n de facturaci&#243;n",   "Adresse de facturation", "Factuuradres"],
    "card_address2" => ["Line 2",   "Espacio 2",   "Ligne 2", "Adresregel 2"],
    "address1" => ["Shipping Address",   "Direcci&#243;&#243;n de modo de enviar",   "Adresse de livraison", "Verzendadres"],
    "address2" => ["Line 2",   "Espacio 2",   "Ligne 2", "Adresregel 2"],
    "city"     => ["City",       "Ciudad",       "Ville", "Stad"],
    "state"    => ["State/Province",      "Estado/Provincia",      "&#201;tat/Province", "Gemeente/Provincie"],
    "province"     => ["International Province",   "Provincia Internacional",   "Province de International", "Internationale Provincie"],
    "zip"      => ["ZipCode/Postal Code",    "C&#243;digo postal",        "Code Postal", "Postcode"],
    "country"  => ["Country",    "Pa&#237;s",    "Pays", "Land"],
    "title"    => ["Title",      "T&#237;tulo",      "Titre", "Titel"],
    "coupon"   => ["Coupon Code",     "C&#243;&#243;digo de cup&#243;n",     "Promo", "Coupon Code"],
    "accttype" => ["Account Type #", "Tipo de cuenta #", "Type de compte #", "Rekening Type"],
    "acctclass"=> ["Account Class",  "Cuenta de clase",  "Classe de comptes", "Rekening klasse"],
    "checktype"=> ["Check Type",  "Cheque Tipo",  "Type de v&#233;rifier", "Cheque Type"],
    "checknum" => ["Check #",     "# de cheque",     "V&#233;rifier #", "Cheque #"],
    "routingnum"   => ["Bank Routing #",  "# de ruta bancaria",  "Banque Routage #", "Bank Routering #"],
    "accountnum"   => ["Checking Account #",  "# de cuenta corriente",  "Compte-ch&#232;ques #", "Betaalrekeningnummer"],
    "licensestate" => ["Drivers Lic. State", "Estado de Licensia de Conducir",  "Pilotes Lic. &#201;tat", "Stad afgifte Rijbewijs"],
    "licensenum"   => ["Drivers Lic. #",  "Controladores Licensia #",  "Pilotes Lic. #", "Rijbewijs nummer"],
    "micr"         => ["MICR",  "MICR",  "MICR", "MICR"],
    "amt_to_pay"   => ["Amount to Pay",     "Importe a pagar",     "Montant &#224; payer", "Bedrag te betalen"],
    "ssnum"        => ["Social Security #",     "Seguro Social #",     "Assurance Sociale #", "Social Security #"],
    "last4"        => ["Last 4 digits of SSN #",  "Los Ultimos 4 Numeros de Seguro Social", "Les 4 derniers chiffres du SIN #", "Laatste 4 cijfers van SSN #"],
    "tran_code"    => ["Transaction Code #",  "# C&#243;&#243;digo de transacci&#243;n",  "Code de transaction #", "Transactie Code #"],
    "walletid"     => ["Wallet ID #",  "Monedero ID #",  "Portefeuille ID #", "Wallet ID #"],
    "passcode"     => ["Passcode", "C&#243;&#243;digo de acceso", "Code d'acc&#232;s", "Toegangscode"],
    "card_type"    => ["Card Type", "Tipo de Tarjeta", "Type de carte", "Card Type"],
    "card_number"  => ["Credit Card #", "N&#250;mero de tarjeta #",  "Carte de cr&#233;dit #", "Creditcard #"],
    "card_cvv"     => ["Credit Card CVV/CVC",  "Tarjeta CVV/CVC",  "Carte de cr&#233;dit CVV/CVC", "Credicard CVV/CVC"],
    "card_exp"     => ["Exp. Date", "Fecha de vencimiento",  "Date d'exp", "Exp. Datum"],
    "cardissuenum" => ["Card Issue #", "Card Issue #",  "Carte num&#233;ro #", "Card Issue #"],
    "cardstartdate"=> ["Card Start Date", "Card Start Date", "Carte Date de d&#233;but", "Card startdatum"],
    "month"        => ["Month",  "Mes", "Mois", "Maand"],
    "year"         => ["Year",  "A&#241;o",  "Ann&#233;e", "Jaar"],
    "dateofbirth"  => ["Date of Birth",  "Fecha de nacimiento",  "Date de naissance", "Geboortedatum"],
    "challenge"    => ["Security Question",  "Cuesti&#243;&#243;n de Seguridad",  "Question de s&#233;curit&#233;", "Veiligheids Vraag"],
    "response"     => ["Answer",  "Respuesta",  "R&#233;ponse", "Antwoord"],
    "mpgiftcard"   => ["Gift Card Number",  "El n&#250;mero de la tarjeta de regalo",  "Num&#233;ro de carte cadeau", "Kadobon code"],
    "mpcvv"        => ["Gift Card Password",  "Contrase&#241;a de la tarjeta de regalo",  "Mot de passe de la carte cadeau", "Kadobon wachtwoord"],
    "ponumber"     => ["PO Number",  "PO N&#250;mero",  "Nombre de PO", "Inkoop Order Nummer"],
    "email"        => ["Email Address",  "Direcci&#243;n de Email",  "Adresse Email", "Email Adres"],
    "phone"        => ["Day Phone #",  "# de Tel&#233;fono de Dia",  "T&#233;l&#233;phone journ&#233;e #", "Telefoonnummer overdag"],
    "phonetype"    => ["Type of Phone",  "Tipo de Tel&#233;fono",  "Type de t&#233;l&#233;phone", "Soort telefoonnummer"],
    "fax"          => ["Night Phone/FAX #",  "# Tel&#233;fono/Fax de Noche",  "De nuit T&#233;l/FAX #", "Telefoonnummer 's avonds"],
    "shipphone"    => ["", "", "", ""],
    "shipfax"      => ["", "", "", ""],
    "help"         => ["Click Here For Help",  "Presione Aqui Para Ayuda",  "Cliquez ici pour aider", "Klik hier voor hulp"],
    "required"     => ["Required for Visa/Mastercard", "Necesario para Visa/Mastercard",  "N&#233;cessaire pour Visa/Mastercard", "Verplicht voor Visa/Mastercard"],
    "selectstate"  => ["Select Your State/Province/Territory",    "Seleccione su estado/provincia/territorio",   "S&#233;lectionnez votre &#233;tat/province/territoire", "Kies uw Gemeente/Provincie/Gebied"],
    "comments"     => ["Comments \&/or Shipping Instructions",  "Comentarios &/o intrucciones de envio",  "Commentaires et/ou Instructions d'exp&#233;dition", "Opmerkingen en/of Verzend instructies"],
    "shipsame"     => ["CHECK HERE if Address is Same as Billing Address", 
                       "Marque Aqu&#237; si la direcci&#243;&#243;n de modo de envi&#243; es igual que la direccion de la factura.", 
                       "V&#201;RIFIER ICI si l'adresse est la m&#234;me que l'adresse de facturation",
                       "VINK HIER AAN indien adres gelijk aan factuuradres"],
    "shipmeth"     => ["Shipping Method",  "M&#233;todo de env&#237;o",  "M&#233;thode d'exp&#233;dition", "Verzendmethode"],
    "ship-insurance" => ["Add shipping insurance", "A&#241;adir un seguro de en&#237;o", "Ajouter l'assurance d'exp&#233;dition", "Voeg verzekering toe"],
    "servlevcode"  => ["Select a Shipping Method",  "Seleccione un m&#233;todo de env&#237;o",  "S&#233;lectionner une m&#233;thode d'exp&#233;dition", "Selecteer een verzendmethode"],
    "deliverydate" => ["Delivery Date", "Fecha de entrega", "Date de livraison", "Leveringsdatum"],
    "novalid"      =>  ["No Valid Shipping Methods Returned.", "No v&#225;lido M&#233;todos de env&#237;o devuelto.",  "Non valide d'exp&#233;dition m&#233;thodes retourn&#233;es.", "Geen geldige verzendmethodes geretourneerd."],
    "submitorder"  => ["Submit Order",  "Someter Orden",  "Soumettre la commande", "Verzend Transactie"],
    "privpol"      => ["Privacy \& Security Policy", "Pol&#237;tica de seguridad y privacidad", "Politique de confidentialit&#233; et s&#233;curit&#233;", "Privacy- \& Beschermings Beleid"],
    "creditpol"    => ["Returns \& Credit Policy", "Returns \& Credit Policy", "Returns & politique de cr&#233;dit", "Retour & Credit Beleid"],
    "ship_pol"     => ["Shipping Policy", "Shipping Policy", "Politique d'exp&#233;dition", "Verzending beleid"],
    "carefully"    => ["Please Check The Following Information Carefully.
                        <br>\nUse the \"Edit Information\" button to make any necessary corrections.",
                       "Por favor revise cuidadosamente la siguiente informaci&#243;n.
                        <br>\nUse el bot&#243;n \"Retroceder\" en su navegador para realizar cualquier correcci&#243;n.",
                       "S'il vous pla&#238;t v&#233;rifier le suivant Information soigneusement. <br> Utiliser le &quot;Modifier les informations&quot; bouton pour effectuer les corrections n&#233;cessaires.",
                       "Gelieve de volgende informatie op nauwkeurigheid te controleren. <br> . Gebruik de \"Edit\" knop om de nodige correcties aan te brengen."],

    "modelnum"     => ["MODEL #", "Modelar #",  "MOD&#200;LE #", "MODEL #"],
    "description"  => ["DESCRIPTION",  "Descripci&#243;n",  "DESCRIPTION", "OMSCHRIJVING"],
    "price"        => ["PRICE",  "Precio",  "PRIX", "PRIJS"],
    "qty"          => ["QTY",  "Cantidad",  "QT&#201;", "AANTAL"],
    "amount"       => ["AMOUNT",  "Monto",  "MONTANT", "BEDRAG"],
    "discount"     => ["DISCOUNT",  "Descuento", "Rabais", "KORTING"],
    "mpgiftcardsummary" => ["Based on the Gift Card balance of <b>[pnp_balance]</b>, this purchase will be applied as follows:",
			    "Based on the Gift Card balance of <b>[pnp_balance]</b>, this purchase will be applied as follows:",
			    "Fond&#233;e sur le solde de la carte cadeau de <b>[pnp_balance]</b>, cet achat sera appliqu&#233;e comme suit:",
                            "Op basis van het kadobon saldo van <b>[pnp_balance]</b>, zal deze aankoop als volgt worden verwerkt:"],
    "mpgiftcardamount"	=> ["GIFT CARD AMOUNT", "GIFT CARD AMOUNT", "MONTANT DE CARTE CADEAU", "KADOBON WAARDE"],
    "creditcardamount"	=> ["CREDIT CARD AMOUNT", "CREDIT CARD AMOUNT", "MONTANT DE LA CARTE DE CR&#201;DIT", "CREDITCARD BEDRAG"],
    "subtotal"     => ["SUBTOTAL", "Subtotal",  "SOUS-TOTAL", "SUBTOTAAL"],
    "shipping"     => ["SHIPPING",  "Transporte",  "EXP&#201;DITION", "VERZENDING"],
    "handling"     => ["HANDLING",  "Cargo por manejo y env&#237;o",  "LA MANIPULATION", "AFHANDELING"],
    "tax"          => ["TAX",  "Impuesto",  "TAXE", "BELASTING"],
    "giftcert"     => ["GIFT CERTIFICATE DISCOUNT",  "Certificado de regalo de descuento",  "CADEAU DISCOUNT", "KADOBON KORTING"],
    "convfee"      => ["CONV. FEE", "Conveniencia de pago",  "Taxe de CONV.", "CONVERSIE KOSTEN"],
    "total"        => ["TOTAL",  "Total",  "TOTAL", "TOTAAL"],
    "continue"     => ["Continue", "Continuar", "Continuer", "Doorgaan"],
    "reset"        => ["Reset Form", "Restablecer formulario", "R&#233;initialiser le formulaire", "Reset Formulier"],
    "submitpay"    => ["Submit Payment", "Enviar Pago", "Soumettre le Paiement", "Betaling Uitvoeren"],
    "summorder"    => ["Summarize Order", "Resumir Orden", "Ordre de R&#233;sumer", "Transactie Afronden"],
    "billinginfo"  => ["<b>Billing Information</b>", "<b>Informaci&#243;n de facturaci&#243;n</b>",  "<b>Information de facturation</b>", "<b>Facturering informatie</b>"],
    "shippinginfo"  => ["<b>Shipping Information</b>", "<b>Informaci&#243;n de Env&#237;o</b>",  "<b>Les informations d'exp&#233;dition</b>", "<b>Verzend informatie</b>"],
    "notice"       => ["NOTICE:", "AVISO:", "AVIS:", "LET OP:"],

    "amttocharge"  => ["Amount to be charged", "Importe a cobrar",  "Montant &#224; payer", "Bedrag af te schrijven"],

    "pleasecopy"   => ["Please copy the following information for your records, it may be slightly different than what you chose:<br>",
                      "Por favor, copie la siguiente informaci&#243;n para sus registros, puede ser ligeramente diferente a lo que eligi&#243;:<br>",
                      "S'il vous pla&#238;t copiez les informations suivantes pour vos dossiers, il peut &#234;tre l&#233;g&#232;rement diff&#233;rente de ce que vous avez choisi:<br>",
                      "Kopieer de volgende informatie voor uw eigen administratie, het kan iets afwijken van uw keuze:<br>"],

    "shipinfo"     => ["Please Enter Your Shipping Information Below",
                       "Por favor, introduzca su informaci&#243;n de env&#237;o a continuaci&#243;&#243;n.",
                       "S'il vous pla&#238;t entrez vos informations de livraison ci-dessous",
                       "Voer uw verzend informatie hieronder"],

    "declined"    =>   ["The transaction was declined for the following reason(s): <br>",
                        "La transacci&#243;&#243;n fue rechazada por el siguiente motivo(s): <br>",
                        "La transaction a &#233;t&#233; refus&#233;e pour les raisons suivantes: <br>",
                        "De transactie werd geweigerd om de volgende reden(en): <br>"],

    "currencyerr1" => ["Invalid currency type specified. Please contact the company you elected to due 
                         business with for ordering assistance.",
                        "Tipo de moneda no es v&#225;lida. P&#243;&#243;ngase en contacto con la empresa que eligi&#243; hacer negocio para asistencia.",
                        "Type de devise non valide sp&#233;cifi&#233;. Veuillez communiquer avec la compagnie vous avez choisi de faire des affaires avec l'aide pour la commande.",
                        "Ongeldige valuta type opgegeven. Gelieve contact op te nemen met het bedrijf waarmee u zaken wilt doenvoor ondersteuning bij uw bestelling."],

    "sorry2"       => ["Sorry for the inconvenience, but the financial processor is currently experiencing delays.  
                        Please wait a few minutes and resubmit your order by clicking on the \"Summarize Order\" button below.",
                       "Lamentamos las molestias, pero el procesador financiero est&#225; experimentando retrasos. Por favor, espere unos minutos 
                        y vuelva a su pedido haciendo clic en el \"Resumir la Orden \" bot&#243;&#243;n de abajo.",  
                       "D&#233;sol&#233; pour la g&#234;ne occasionn&#233;e, mais le processeur financier conna&#238;t actuellement des retards.
                        S'il vous pla&#238;t, attendez quelques minutes et soumettre &#224; nouveau votre commande en cliquant sur le bouton &#171; Commander r&#233;sumer &#187; ci-dessous.",
                       "Sorry voor het ongemak, de financial processor ondervind momenteel vertraging. Gelieve over enkele minuten uw order opnieuw aan te bieden door te klikken op de knop \"Transactie Afronden\"."],

    "billing"      => ["Please Enter Your Billing Information Below\:",
                       "Por favor, introduzca su informaci&#243;n de facturaci&#243;n a continuaci&#243;n\:",
                       "S'il vous pla&#238;t entrer votre facturation informations ci-dessous:",
                       "Vul uw facturering informatie hieronder:"],

    "billing1"     => ["Required fields are marked with an asterisk <b>(*)</b>.",
                       "Espacios que requieren informaci&#243;n son marcados con un <b>(*)</b>.",
                       "Requis sont marqu&#233;s d'un ast&#233;risque <b>(*)</b>.",
                       "Verplichte velden zijn gemarkeerd met een sterretje <b>(*)</b>."],

    "subscription" => ["Please Enter Your Subscription Information Below",
                       "Please Enter Your Subscription Information Below",
                       "Veuillez entrer vos informations d'abonnement ci-dessous",
                       "Voer uw abonnement informatie hieronder"],

    "pleaseship"   => ["Please Enter Your Shipping Information Below",  
                       "Por favor escriba la informaci&#243;n de modo de envio debajo",  
                       "S'il vous pla&#238;t entrez vos informations de livraison ci-dessous",
                       "Vul uw verzend informatie hieronder"],

    "patience1"   => ["We appreciate your patience while your order is processed. It should take less than 1 minute. 
                        Please press the \"Submit Order\" only once to prevent any potential double billing.
                        If you have a problem please email us at",
                       "Apreciamos su paciencia mientras su orden es procesada. Debe de tomar menos de un minuto.
                        Por favor toque el bot&#243;&#243;n de \"Someter Orden\" solamente una vez para evitar cobro doble de su factura (cuenta).
                        Si experimenta alg&#250;n problema favor de comunicarlo por email a",
                       "Nous appr&#233;cions votre patience pendant que votre commande est trait&#233;e. Il devrait prendre moins d'une minute.
                        Veuillez appuyer sur le &#171; soumettre la commande &#187; qu'une seule fois pour &#233;viter toute &#233;ventuelle double facturation.
                        Si vous avez un probl&#232;me s'il vous pla&#238;t envoyez-nous un courriel &#224;",
                       "We vragen een moment geduld terwijl we uw transactie verwerken. De verwerking zou niet langer dan 1 minuut moeten duren.
                        Gelieve maar &eacute;&eacute;n keer op de \"Verzend Transactie\" knop te klikken om te voorkomen dat u dubbel wordt gefactureerd.
                        Indien u tegen een probleem aanloopt kunt u emailen naar"],

    "patience2"   => ["Please give your full name, order number (if you received a purchase confirmation), 
                        and the exact nature of the problem.",
                       "Por favor escriba su nombre completo, n&#250;mero de orden (si ud. recibi&#243;&#243; la confirmaci&#243;n de compra), 
                        y una descripci&#243;&#243;n del problema.", 
                       "S'il vous pla&#238;t donner votre nom, pr&#233;nom, num&#233;ro de commande (si vous avez re&#231;u une confirmation de l'achat) et la nature exacte du probl&#232;me.",
                       "Please give your full name, order number (if you received a purchase confirmation), and the exact nature of the problem."],

    "pleaseenter" => ["<br>Please Enter Your Desired Username &amp; Password Below:<br>",  
                       "<br>Favor de escoger y registrar su nombre de usuario y palabra clave debajo:<br>", 
                       "<br>S'il vous pla&#238;t entrer votre nom d'utilisateur souhait&#233; &amp; Mot de passe ci-dessous:<br>",
                       "<br>Voer hieronder uw gewenste Gebruikersnaam &amp; Wachtwoord:<br>"],

    "unpasswrd1"   =>  ["Usernames and Passwords CAN NOT be the same, are restricted to a maximum of [pnp_unpw_maxlength] characters and ",
                         "Nombres de usuario y palabras claves NO PUEDEN se iguales, son restrinjidas a un m&#225;ximo de [pnp_unpw_maxlength] letras y",
                         "Noms d'utilisateur et mots de passe ne peuvent pas &#234;tre identiques, sont limit&#233;s &#224; un maximum de [pnp_unpw_maxlength] caract&#232;res et ",
                         "Gebruikersnaam en Wachtwoord mogen NIET gelijk zijn, zijn beperkt tot maximaal [pnp_unpw_maxlength] tekens en"],

    "unpasswrd2"   =>  [" <b class=\"badcolor\">  usernames MUST contain both UPPER \/ lower case letters and numbers.",
                         " Nombres de usuarios NECESITAN contener letras y n&#250;meros.",
                         " <b class=\"badcolor\"> nom d'utilisateur doit contenir des majuscules / minuscules lettres et chiffres.",
                         " <b class=\"badcolor\"> gebruikersnaam MOET zowel HOOFDLETTERS / kleine letters en nummers bevatten."],

    "unpasswrd3"   =>  ["can contain only <b class=\"badcolor\">letters and\/or numbers.",
                        "Pueden contener solo <b class=\"badcolor\">letras y\/o n&#250;meros.",
                        "peut contenir seulement <b class=\"badcolor\">lettres et/ou de chiffres.",
                        "kan alleen <b class=\"badcolor\">letters en/of nummers bevatten."],

    "unpasswrd4"   =>  ["Any blank spaces or special characters (\*,\!,\#,\? etc... ) </b>will be removed. 
                          Please enter your choices accordingly.  
                          You will receive an email with your Username and Password for your records",
                         "Cualquier espacio en blanco o signos especiales (\*,\!,\#,\? etc... ) </b>ser&#225;n eliminados. 
                          Favor de registrar su selecci&#243;&#243;n comotal. 
                          Ud.  recibir&#225; un email con su nombre de usuario y palabra clave para sus registros.",
                         "Blanc d'espaces ou de caract&#232;res sp&#233;ciaux (\*,\!,\#,\? etc... ) </b>seront supprim&#233;es.
                          Veuillez entrer vos choix en cons&#233;quence.
                          Vous recevrez un email avec votre nom d'utilisateur et mot de passe pour vos dossiers",
                         "Voorkomens van spaties of speciale tekens (\*,\!,\#,\? etc... ) </b>zullen verweiderd worden. Voer uw keuze in. U ontvangt een e-mail met uw gebruikersnaam en wachtwoord voor uw administratie"],

    "unpasswrd5"    =>   ["Remember, Usernames and Passwords are CASE SENSITIVE.<p>\n
                           You will receive an email confirmation of this purchase which will contain an ORDER ID 
                           as well as a copy of your username and password. \n
                           It is VERY IMPORTANT that you save this email.  This information will be required if you experience any problems. \n
                           If you entered an incorrect email address, please use the back button and go back and change it.</b><br>\n",
                          "Recuerde, nombres de usuario y contrase&#241;as distinguen entre may&#250;sculas y min&#250;sculas.<p>\n 
                           Usted recibir&#225; un correo electr&#243;nico de confirmaci&#243;n de esta compra que contendr&#225; un ID 
                           del pedido, as&#237; como una copia de su nombre de usuario y contrase&#241;a.\n
                           Es muy importante que guarde este mensaje de correo electr&#243;nico. 
                           Esta informaci&#243;n ser&#225; necesaria en caso de experimentar cualquier problema. \n 
                           Si ha introducido una direcci&#243;n de correo electr&#243;nico incorrecta, por favor, utilice el bot&#243;n Atr&#225;s y volver atr&#225;s y cambiarlo.</b><br>\n",
                          "Rappelez-vous, les noms d'utilisateur et les mots de passe sont sensibles &#224; la casse.<p>\n
                           Vous recevrez un email de confirmation de cet achat qui contient un ID d'ordre ainsi qu'une copie de votre nom d'utilisateur et mot de passe. \n
                           Il est TR&#200;S IMPORTANT que vous enregistrez cet email. Cette information est n&#233;cessaire si vous rencontrez des probl&#232;mes.\n
                           Si vous avez entr&#233; une adresse email incorrecte, veuillez utiliser le bouton retour et revenir en arri&#232;re et modifier it.</b><br>\n",
                          "Denk eraan, Gebruikersnamen en Wachtwoorden zijn HOOFDLETTER GEVOELIG.<p> Un ontvangt een bevestigings e-mail
                           van deze aankoop met hierin een BESTELLING ID en ook een kopie van uw gebruikersnaam en wachtwoord.
                           Het is ZEER BELANGRIJK dat u dit e-mail bericht bewaart. Deze informatie zal nodig zijn mocht u klachten hebben.
                           Indien u een incorrect e-mailadres heeft ingevoerd, gebruik de terug knop en wijzig deze.</b><br>"],


    "infoproblem"  =>  ["There seems to be a problem with the information you entered.",  
                         "Parece haber un problema con la informaci&#243;n que Ud. ha dado.", 
                         "Il semble y avoir un probl&#232;me avec les informations que vous avez entr&#233;es.",
                         "Er lijkt een probleem te zijn met de informatie die u heeft ingevoerd."],

    "validcc"     =>   ["The number you entered is NOT a valid credit card number.  
                          Please re-enter your credit card number and check it closely before resubmitting your order.",
                         "El # que Ud. a registrado NO es un # v&#225;lido de tarjeta de cr&#233;dito.  
                          Favor de revisar su # de su tarjeta de cr&#233;dito antes de registr arla de nuevo.",
                         "Le nombre que vous avez entr&#233; n'est pas un num&#233;ro de carte de cr&#233;dit valide.
                          S'il vous pla&#238;t, entrez &#224; nouveau votre num&#233;ro de carte de cr&#233;dit et v&#233;rifiez-le attentivement avant de soumettre votre commande.",
                         "Het door u ingevoerd nummer is GEEN geldige creditcard nummer.
                          Gelieve uw creditcard nummer opnieuw in te voeren nadat deze gecontroleerd is en verzend uw transactie nogmaails."],

    "sorry1"      =>   ["Sorry - We are currently not authorized to accept that credit card type.  
                          Please choose another card. Thank You.",
                         "Lo sentimos.- No estamos actualmente autorizados para aceptar este tipo de tarjeta de cr&#233;dito  
                          Favor de escojer otra tarjeta. Gracias.",
                         "D&#233;sol&#233; - nous ne sommes actuellement pas autoris&#233;s &#224; accepter ce type de carte de cr&#233;dit.
                          Veuillez choisir une autre carte. Merci.",
                         "Sorry - We zijn momenteel niet geautoriseerd om uw creditkaart type te accepteren. Gelieve een andere kaart te selecteren. Bedankt."],

    "incorrect"   =>   ["If you feel that you may have entered your billing information incorrectly 
                          or if you wish to use another card, Please Re-Enter the Information below.<br>",
                         "Si Ud. piensa que ha registrado incorrectamente la informaci&#243;n de cobro 
                          o si Ud. quisiera usar otra tarjeta, favor de registrar de nuevo la informaci&#243;n debajo.<br>",
                         "Si vous pensez que vous avez peut-&#234;tre saisi vos informations de facturation incorrecte
                          ou si vous souhaitez utiliser une autre carte, veuillez saisir de nouveau les informations ci-dessous.<br>",
                         "Indien u van mening bent dat u wellicht incorrecte facturerings informatie heeft ingevoerd of u wenst gebruik te maken van een andere kaart, gelieve de informatie hieronder nogmaals in te voeren.<br>"], 
    "inerror"     =>   ["If you feel this message is in error please call your credit card issuer for assistance.<br>",
                         "Si Ud. piensa que este mensaje es un error favor de llamar a la compa&#241;&#237;a de su tarjeta de cr&#233;dito. para asistencia.<br>",
                         "Si vous pensez que ce message est dans l'erreur veuillez appeler votre &#233;metteur de carte de cr&#233;dit pour assistance.<br>",
                         "Indien u van mening bent dat de foutmelding incorrect is, gelieve contact op te  nemen met uw creditcard maatschappij.<br>"],
    "mpgifterror" =>   ["Please re-enter your Gift Card to try it again or leave it blank to charge the full amount on the credit card.",
			 "Please re-enter your Gift Card to try it again or leave it blank to charge the full amount on the credit card.",
			 "S'il vous pla&#238;t entrer de nouveau votre carte-cadeau pour essayer &#224; nouveau ou de laisser le champ vide pour facturer le plein montant sur la carte de cr&#233;dit.",
                         "Vul uw kadobon gegevens nogmaals in om het opnieuw te proberen of laat het leeg om het volledige bedrag van uw creditcard af te schrijven."], 
    "mpgiftinvalid" => ["Invalid Gift Card number or password.", "Invalid Gift Card number or password.", "Num&#233;ro de carte cadeau non valide ou mot de passe.", "Ongeldig kadobon code of wachtwoord."],

    "reqinfo"     =>   ["Some Required Information has not been filled in correctly.  
                          <br>Please re-enter the information in the <b class=\"badcolor\">
                          fields marked in [pnp_badcolortxt]</b>",
                         "La informaci&#243;n necesaria no ha sido registrada correctamente.  
                          <br>Favor de registrar de nuevo la informaci&#243;n en los <b class=\"badcolor\">
                          espacios marcados en [pnp_badcolortxt]</b>",
                         "Certaines informations requises n'ont pas &#233;t&#233; correctement remplis.
                          <br> Veuillez saisir de nouveau vos informations dans le <b class=\"badcolor\">
                          les champs marqu&#233;s en [pnp_badcolortxt]</b>",
                         "Sommige verplichte informatie is niet correct ingevoerd.
                          <br>Voer de in <b class=\"badcolor\"> gemarkeerde velden opnieuw in [pnp_badcolortxt]</b>"],

    "billaddrerr" =>   ["The Zip Code and State for your billing address do not match.",
                         "Su n&#250;mero de Zip y Estado para su direccion de cobro no es igual.",
                         "Le Code postal et l'&#233;tat de votre adresse de facturation ne correspondent pas.",
                         "De postcode en plaats van uw verzendadres komen niet overeen."],
    "shipadderr"  =>   ["The Zip Code and State for your shipping address do not match.",
                         "Su n&#250;mero de Zip y Estado para envio no es igual.",
                         "Le Code postal et l'&#233;tat de votre adresse de livraison ne correspondent pas.",
                         "De Postcode en Plaats voor uw verzendadres komen niet overeen."],

    "passwrderr1" =>   ["Passwords Can Not Contain Less Than [pnp_unpw_minlength] Characters - Please Re-enter.",
                         "Su palabra clave NO puede tener menos de [pnp_unpw_minlength] letras.- Favor de registrarla de nuevo.",
                         "Les mots de passe ne peuvent pas contenir moins de [pnp_unpw_minlength] caract&#232;res - Veuillez r&#233;-entrer.",
                         "Het wachtwoord moet minimaal [pnp_unpw_minlength] tekens bevatten.  Voer een nieuw wachtwoord in."],

    "passwrderr2" =>   ["Characters - Please Re-enter.",
                         "letras.- Favor de registrarla de nuevo.",
                         "Caract&#232;res - Veuillez entrer de nouveau.",
                         "Tekens - Voer opnieuw in."],

    "passwrderr3" =>   ["Passwords Do Not Match - Please Re-enter.",
                         "La palabra clave no es igual.- Favor de registrarla de nuevo.",
                         "Mots de passe faire pas Match - Veuillez entrer de nouveau.",
                         "Wachtwoorden komen niet overeen - Probeer het opnieuw"],

    "username"    =>   ["Username",  "El nombre de usuario", "Nom d'utilisateur", "Gebruikersnaam"],
    "password"    =>   ["Password", "La palabra", "Mot de passe", "Wachtwoord"],

    "inuse"       =>   ["Already in Use.",  "Est&#225; en uso actualmente.",  "D&#233;j&#224; en cours d'utilisation.", "Reeds in gebruik"],

    "passwrderr4" =>   ["Usernames and Passwords are not allowed to match.", 
                         "La palabra clave y el nombre del usuario no pueden ser iguales.",
                         "Noms d'utilisateur et mots de passe ne sont pas autoris&#233;s &#224; correspondre.",
                         "Gebruikersnaam en wachtwoord mogen niet gelijk zijn."],

    "passwrderr5" =>   ["Username must contain both Characters and Numbers.", 
                         "El nombre de usuario necesita incluir letras y n&#250;meros.", 
                         "Nom d'utilisateur doit contenir des caract&#232;res et des chiffres.",
                         "Gebruikersnaam moet zowel alfanumerieke- als nummerieke tekens bevatten."],

    "passwrderr6" =>   ["Password must contain both Characters and Numbers.",  
                         "La palabra clave necesita incluir letras y n&#250;meros.", 
                         "Mot de passe doit contenir des caract&#232;res et des chiffres.",
                         "Wachtwoord moet zowel alfanumerieke- als nummerieke tekens bevatten."],

    "re_enter1"   =>   ["Please Re-enter.",  "Favor de registrarla de nuevo.", "S'il vous pla&#238;t entrer de nouveau.", "Gelieve opnieuw in te voeren."],
    "re_enter2"   =>   ["<br>Please re-enter the information in the <b style=\"color: [pnp_badcolor]\">fields marked in [pnp_badcolortxt]</b>.<br><br>",
                        "<br>Please re-enter the information in the <b style=\"color: [pnp_badcolor]\">fields marked in [pnp_badcolortxt]</b>.<br><br>",
                        "<br>Please re-enter the information in the <b style=\"color: [pnp_badcolor]\">fields marked in [pnp_badcolortxt]</b>.<br><br>",
                        "<br>Gelieve de informatie in de met <b style=\"color: [pnp_badcolor]\">gemarkeerde velden in [pnp_badcolortxt]</b>.<br><br>"],

    "privacy"     =>   ["<b>NOTICE:</b> It is the policy of [pnp_company] to respect the privacy of its 
                          customers and the people doing business through its service.  
                          As such all information presented here WILL NOT be sold or distributed to any party other 
                          than the merchant you have currently elected to do business with.",
                         "<b>ATENCION:</b> Es la regla de [pnp_company] respetar la privacidad de sus clientes y 
                          personas que utilicen este medio para llevar a cabo sus compras. Toda informaci&#243;n presentada aqui 
                          NO SERA VENDIDA o distribuida a ninguna otra entidad o persona sino solamente a la que usted ha seleccionado.", 
                         "<b>AVIS:</b> c'est la politique de [pnp_company] &#224; respecter la vie priv&#233;e de ses
                          clients et les gens qui font des affaires par le biais de son service.
                          En tant que telles toutes les informations pr&#233;sent&#233;es ici ne seront pas vendus ou distribu&#233;s &#224; toute partie autre
                          que le commer&ccedil;ant vous avez actuellement &#233;lus pour faire affaire avec.",
                         "<b>LET OP:</b> Het beleid van [pnp_company] is om de privacy van zijn klanten en partijen die zaken doen via hun service te respecteren.
                          Hierdoor zal alle informatie die hier gepresenteerd is NIET verkocht worden of gedeeld worden met enige partijen anders dan degene waarmee u gekozen heeft zaken mee te doen."],
 
    "giftstatement" => ["If you have a Gift Card you may enter it here instead of a credit card. 
                          If your Gift Card balance is insufficient for the entire purchase amount 
                          you may enter your Credit Card details as well.  Any amount still outstanding 
                          after your gift card has been charged will be applied against your credit card.",
                         "Si usted tiene una tarjeta de regalo puede entrar aqu&#237; en lugar de una tarjeta de cr&#233;dito. 
                          Si su tarjeta de regalo de saldo es insuficiente para comprar la totalidad del monto usted puede 
                          entrar su tarjeta de cr&#233;dito tambi&#233;n. Cualquier cantidad pendiente de percibir despu&#233;s de que su 
                          tarjeta de regalo se ha cargado se aplicar&#225; en contra de su tarjeta de cr&#233;dito.",
                         "Si vous avez une carte-cadeau, vous pouvez l'entrer ici au lieu d'une carte de cr&#233;dit.
                          Si votre solde de carte-cadeau est insuffisant pour l'ensemble du montant d'achat
                          vous pouvez entrer les d&#233;tails de votre carte de cr&#233;dit ainsi. Tout montant en souffrance apr&#232;s
                          que votre carte-cadeau a &#233;t&#233; factur&#233; sera appliqu&#233;e contre votre carte de cr&#233;dit.",
                         "Indien u een kadobon heeft, kunt u deze hier invoeren in plaats van uw creditcard.
                          Indien het saldo van uw kadobon ontoereikend is voor het gehele aankoopbedrag kunt u ook uw kreditkaart gegevens invoeren.
                          Een eventuele resterende bedrag na afschrijving van uw kadobon saldo komt ten laste van uw creditcard."],

    "lowbalance" => ["Your current Gift Card balance of [pnp_balance] is insufficent to complete your purchase. 
                          In order to complete the purchase you will need to enter your Credit Card details as well.  The amount still outstanding 
                          after your gift card has been charged will be applied against your credit card.",
                         "Your current Gift Card balance of [pnp_balance] is insufficent to complete your purchase. 
                          In order to complete the purchase you will need to enter your Credit Card details as well.  The amount still outstanding 
                          after your gift card has been charged will be applied against your credit card.",
                         "Votre carte cadeau actuelle balance des [pnp_balance] est insuffisant pour effectuer votre achat.
                          Afin de proc&#233;der &#224; l'achat, vous devrez entrer vos d&#233;tails de carte de cr&#233;dit ainsi. Le montant restant &#224; liquider apr&#232;s
                          que votre carte-cadeau a &#233;t&#233; factur&#233; sera imput&#233; &#224; votre carte de cr&#233;dit.",
                         "Uw kadobon saldo van [pnp_balance] is ontoereikend om uw aankoop af te ronden.
                          Om uw transactie af te ronden dient U ook uw creditcard gegevens in te voeren.
                          Het nog openstaand bedrag na afboeken van uw kadobon saldo zal afgeboekt worden van uw creditcard."],

   "namecheck"      =>  ["Name must contain your name as it's printed on the credit card.",
                         "El nombre debe contener su nombre tal y como es impreso en la tarjeta de cr&#233;dito.",
                         "Nom doit contenir votre nom tel qu'il est imprim&#233; sur la carte de cr&#233;dit.",
                         "Naam moet ingevoerd worden zoals deze op de creditcard is aangegeven."],
   "nogiftcard"     =>  ["No Gift Card number entered or invlaid length.",
                         "Falta el n&#250;mero de la tarjeta de regalo o la longitud no es v&#225;lido.",
                         "Carte-cadeau sans num&#233;ro longueur inscrite ou non valide.",
                         "Geen kadobon code ingevoerd of ongeldige lengte."],
   "psldob"         =>  ["Sorry, the Date of Birth entered is invalid. Proper Format is: MM/DD/YYYY",
                         "Lo sentimos, la fecha de nacimiento que introdujo no es v&#225;lido. Formato adecuado es: DD/MM/YYYY",
                         "D&#233;sol&#233;, la date de naissance saisie est incorrecte. Format ad&#233;quat est: MM/DD/YYYY",
                         "Sorry, de ingevoerde geboortedatum is ongeldig. Het juiste formaat is: MM/DD/YYYY"],
   "pslphone"       =>  ["Sorry, invalid phone type.", "Sorry, invalid phone type.", "D&#233;sol&#233;, type de t&#233;l&#233;phone non valide.", "Sorry, ongeldig telefoon type."],
   "pslwalletid"    =>  ["Sorry, the WalletID and Email address must match.",
                         "Lo sentimos, pero la WalletID y direcci&#243;n de correo electr&#243;nico deben coincidir.",
                         "D&#233;sol&#233;, doit correspondre &#224; l'adresse WalletID et le courrier &#233;lectronique.",
                         "Sorry, de WalletID en E-mailadres moeten overeenkomen."],
   "acctnumerr"     =>  ["Account Number has too few characters.", "N&#250;mero de Cuenta no ha suficientes caracteres.", "Num&#233;ro de compte a trop peu de caract&#232;res.", "Rekeningnummer is te kort."],
   "routnumerr"     =>  ["Invalid Routing Number.  Please check and re-enter.", 
                         "N&#250;mero de enrutamiento no es v&#225;lido. Por favor, compruebe y volver a entrar.", 
                         "Num&#233;ro de routage non valide. S'il vous pla&#238;t v&#233;rifier et re-entrer.",
                         "Ongeldig Routering Nummer. Graag controleren en opnieuw invoeren."],
   "checknumerr"    =>  ["Check Number has to few digits.", "El n&#250;mero sobre de cheque es a corto.", "V&#233;rifier nombre a &#224; quelques chiffres.", "Cheque nummer is te kort."],
   "destnotallowed" =>  ["Choosen shipping method  not allowed for destination country.",
                         "Elegido m&#233;todo de env&#237;o no permitido para los pa&#237;ses de destino.",
                         "Mode de livraison choisi ne pas autoris&#233;e pour les pays de destination.",
                         "Gekozen verzendmethode niet toegestaan voor het land van bestemming."],
   "makechange"     =>  ["Edit Information",
                         "Edit Information",
                         "Modifier les informations",
                         "Gegevens bewerken"],


  );


  ## Languange For Billing Presentment
  %language::billpay_titles = (
    # Service Titles & Sub-Titles
    "service_title"                  => ["Billing Presentment", "", ""],
    "service_subtitle_billdetails"   => ["Bill Details", "", ""],
    "service_subtitle_billoptions"   => ["Billing Profile Options", "", ""],
    "service_subtitle_reportresults" => ["Report Results", "", ""],
    "service_subtitle_billlistings"  => ["Bill Listings", "", ""],
    "service_subtitle_autopay"       => ["Automatic Payments", "", ""],
    "service_subtitle_paybills"      => ["Bill Payment Adminstration", "", ""],
    "service_subtitle_viewbills"     => ["Bill Viewing Adminstration", "", ""],
    "service_subtitle_custprofile"   => ["Customer Profile Adminstration", "", ""],
    "service_subtitle_billprofile"   => ["Billing Profiles Adminstration", "", ""],
    "service_subtitle_docs"          => ["Documentation", "", ""],
    "service_subtitle_help"          => ["Help Info", "", ""],

    # Field Legends
    "legend_customer"       => ["Customer:", "", ""],
    "legend_invoiceinfo"    => ["Invoice Info:", "", ""],
    "legend_paymentdetails" => ["Payment Details", "", ""],
    "legend_shipping"       => ["Shipping Address:", "", ""],

    # Section Tables - Titles & Columns
    "section_productdetails" => ["Product Details", "", ""],
    "column_item"        => ["Item", "", ""],
    "column_descr"       => ["Description", "", ""],
    "column_qty"         => ["Qty", "", ""],
    "column_cost"        => ["Unit Cost", "", ""],
    "column_weight"      => ["Unit Weight", "", ""],
    "column_descra"      => ["Attribute #1", "", ""],
    "column_descrb"      => ["Attribute #2", "", ""],
    "column_descrc"      => ["Attribute #3", "", ""],
    "column_merchant"    => ["Merchant", "", ""],
    "column_username"    => ["Username", "", ""],
    "column_invoice_no"  => ["Invoice Number", "", ""],
    "column_enterdate"   => ["Enter Date", "", ""],
    "column_expiredate"  => ["Expire Date", "", ""],
    "column_account_no"  => ["Account Number", "", ""],
    "column_amount"      => ["Amount", "", ""],
    "column_tax"         => ["Tax", "", ""],
    "column_shipping"    => ["Shipping", "", ""],
    "column_handling"    => ["Handling", "", ""],
    "column_discount"    => ["Discount", "", ""],
    "column_balance"     => ["Balance", "", ""],
    "column_installment" => ["Installment", "", ""],
    "column_remnant"     => ["Remnant", "", ""],
    "column_status"      => ["Status", "", ""],

    "section_overview"         => ["Account Overview - Bills:", "", ""], 
    "section_overview_open"    => ["Open", "", ""],
    "section_overview_expired" => ["Expired", "", ""],
    "section_overview_closed"  => ["Closed", "", ""],
    "section_overview_paid"    => ["Paid", "", ""],
    "section_paybills"         => ["Pay Outstanding Bills", "", ""],
    "section_viewbills"        => ["View Bills Administration", "", ""],
    "section_custprofile"      => ["Customer Profile Administration", "", ""],
    "section_billprofile"      => ["Billing Profiles Administration", "", ""],
    "section_docs"             => ["Documentation", "", ""],
    "section_gencontact"       => ["General Contact Information", "", ""],
    "section_shipcontact"      => ["Shipping Contact Information", "", ""],
    "section_instcontact"      => ["Instant Contact Information", "", ""],
    "section_misccontact"      => ["Misc. Information", "", ""],
    "section_security"         => ["Security","",""],
    "section_billcontact"      => ["Billing Address Information", "", ""],
    "section_ccinfo"           => ["Credit Card Information", "", ""],
    "section_achinfo"          => ["ACH Billing Information", "", ""],
    "section_miscinfo"         => ["Misc. Information", "", ""],
    "section_orderreceipt"     => ["Order Receipt", "", ""],
    "section_billinginfo"      => ["Billing Information", "", ""],
    "section_shippinginfo"     => ["Shipping Information", "", ""],

    "section_terms_pay"        => ["Payment Terms \& Conditions", "", ""],
    "section_terms_service"    => ["Terms of Service", "", ""],
    "section_terms_use"        => ["Acceptable Use Policy", "", ""],
    "section_terms_privacy"    => ["Privacy Policy", "", ""],

    "section_balance_amount"      => ["Invoice Balance", "", ""],
    "section_payment_amount"      => ["Apply Payment", "", ""],

    # Section Descriptions
    "description_paybills"        => ["View outstanding bills and pay for them online.", "", ""],
    "description_viewbills"       => ["Review your bills within the database; including viewing/paying outstanding bills \& reviewing paid bills.", "", ""],
    "description_custprofile"     => ["Administrate your customer profile's contact info \& other settings.", "", ""],
    "description_billprofile"     => ["Administrate your billing profiles.", "", ""],
    "description_docs"            => ["Easy access to support documentation, FAQ & helpdesk for using this service.", "", ""],
    "description_billsame"        => ["Select this, if your Billing Address Information is same as the General Contact Information.", "", ""],
    "description_shipsame"        => ["Select this, if your Shipping Contact Information is same as the General Contact Information.", "", ""],
    "description_optout_reminder" => ["Select to opt-out from receiving invoice payment reminders, sent by some participating merchants.", "", ""],

    # Menu Section Titles
    "menu_docs"             => ["Documentation", "", ""],
    "menu_faq"              => ["Frequently Asked Questions", "", ""],
    "menu_helpdesk"         => ["Online Helpdesk", "", ""],
    "menu_login"            => ["Account Login", "", ""],
    "menu_list_open"        => ["List Open/Unpaid Bills", "", ""],
    "menu_list_expired"     => ["List Expired Bills", "", ""],
    "menu_list_closed"      => ["List Closed Bills", "", ""],
    "menu_list_paid"        => ["List Paid Bills", "", ""],
    "menu_autopay"          => ["Auto-Pay Bills", "", ""],
    "menu_view_contact"     => ["View Contact Profile", "", ""],
    "menu_edit_contact"     => ["Edit Contact Profile", "", ""],
    "menu_list_billing"     => ["List Billing Profiles", "", ""],
    "menu_edit_billing"     => ["Edit Billing Profiles", "", ""],
    "menu_add_billing"      => ["Add Billing Profile", "", ""],
    "menu_delete_billing"   => ["Delete Billing Profile", "", ""],
    "menu_profiles"         => ["Profiles", "", ""],
    "menu_bills"            => ["Bills", "", ""],
    "menu_activate_autopay" => ["Activate Automatic Payments", "", ""],
    "menu_delete_autopay"   => ["Disable Automatic Payments", "", ""],

    # Field Titles
    "invoice_no"       => ["Invoice No:", "", ""],
    "account_no"       => ["Account No:", "", ""],
    "enterdate"        => ["Enter Date:", "", ""],
    "expiredate"       => ["Expire Date:", "", ""],
    "status"           => ["Status:", "", ""],
    "orderid"          => ["OrderID:", "", ""],
    "monthly"          => ["Installment Amount:", "", ""],
    "percentage"       => ["Installment Percentage:"],
    "remnant_due"      => ["Remnant Due:", "", ""],
    "installment_min"  => ["Minimum Installment:", "", ""],
    "installment_fee"  => ["Installment Fee:"],
    "installment_due"  => ["Amount Due:", "", ""],
    "balance"          => ["Current Balance:", "", ""],
    "remain_balance"   => ["Remaining Balance", "", ""],
    "billcycle"        => ["Billing Cycle:", "", ""],
    "lastbilled"       => ["Last Charged:", "", ""],
    "lastattempted"    => ["Last Attempted:", "", ""],
    "subtotal"         => ["Subtotal:", "", ""],
    "shipping"         => ["Shipping:", "", ""],
    "handling"         => ["Handling:", "", ""],
    "discount"         => ["Discount:", "", ""],
    "tax"              => ["Tax:", "", ""],
    "amount"           => ["Order Total:", "", ""],
    "datalink"         => ["Related Document(s):", "", ""],
    "public_notes"     => ["Notes:", "", ""],
    "comments"         => ["Comments:", "", ""],
    "srch_email"       => ["Email Address:", "", ""],
    "srch_invoice_no"  => ["Invoice Number:", "", ""],
    "retrieve_invoice" => ["Retrieve Invoice:", "", ""],
    "payment_remnant"  => ["Remnant:", "", ""],
    "payment_min"      => ["Min Payment:", "", ""],
    "payment_max"      => ["Max Payment:", "", ""],
    "payment_amt"      => ["Your Payment Amount:", "", ""],
    "payment_date"     => ["Payment Date:", "" ,""],
    "morderid"         => ["Merchant ID:", "", ""],
    "totalwgt"         => ["Total Weight:", "", ""],

    "name"             => ["Name:", "", ""],
    "company"          => ["Company:", "", ""],
    "address1"         => ["Address Line 1:", "", ""],
    "address2"         => ["Address Line 2:", "", ""],
    "city"             => ["City:", "", ""],
    "state"            => ["State:", "", ""],
    "zip"              => ["Zipcode:", "", ""],
    "country"          => ["Country:", "", ""],
    "shipname"         => ["Name:", "", ""],
    "shipaadr1"        => ["Address Line 1:", "", ""],
    "shipaddr2"        => ["Address Line 2:", "", ""],
    "shipcity"         => ["City:", "", ""],
    "shipstate"        => ["State:", "", ""],
    "shipzip"          => ["Zipcode:", "", ""],
    "shipcountry"      => ["Country:", "", ""],
    "phone"            => ["Phone:", "", ""],
    "fax"              => ["Fax:", "", ""],
    "email"            => ["Email:", "", ""],
    "password"         => ["Password:", "", ""],
    "password2"        => ["Confirm Password:", "", ""],
    "acctstatus"       => ["Account Status", "", ""],
    "optout_reminder"  => ["Reminder Out-Out:", "", ""],
    "captcha"          => ["CAPTCHA:", "", ""],
    "captcha_answer"   => ["Answer:", "", ""],
    "cardnumber"       => ["Card Number:", "", ""],
    "exp"              => ["Exp Date:", "", ""],
    "routingnum"       => ["Routing Number:", "", ""],
    "accountnum"       => ["Bank Account Number:", "", ""],
    "accttype"         => ["Account Type:", "", ""],
    "billusername"     => ["Bill Username:", "", ""],
    "reason"           => ["Reason:", "", ""],
    "authcode"         => ["Auth Code:", "", ""],

    "alias"            => ["Alias:", "", ""],

    # Hyperlink Titles
    "link_home"        => ["Home", "", ""],
    "link_logout"      => ["Logout", "", ""],
    "link_help"        => ["Help", "", ""],
    "link_paybills"    => ["Pay Outstanding Bills", "", ""], 
    "link_viewbills"   => ["View Bills Administration", "", ""],
    "link_custprofile" => ["Customer Profile Administration", "", ""],
    "link_billprofile" => ["Billing Profiles Administration", "", ""],
    "link_docs"        => ["Documentation", "", ""],
    "link_clickbegin"  => ["Click here to begin", "", ""],
    "link_faq"         => ["Frequently Asked Questions", "", ""],
    "link_helpdesk"    => ["Online Helpdesk", "", ""],
    "link_changepass"  => ["Change Login Password", "", ""],
    "link_add_billprofile" => ["CLICK HERE to add a billing profile.", "", ""],
    "link_billprofmenu" => ["Back To Billing Profiles Administration", "", ""],
    "link_custprofmenu" => ["Back To Customer Profile Administration", "", ""],
    "link_autopaymenu"  => ["Back To Auto-Pay Bills Administration", "", ""],
    "link_clickhere"    => ["CLICK HERE", "", ""],
    "link_datalink"     => ["Additional Information", "", ""],

    "emailcust_link_viewinvoice" => ["Click Here To View Invoice", "", ""],
    "emailcust_link_signup"      => ["Click Here To Sign-Up", "", ""],
    "emailcust_link_expresspay"  => ["Click Here To Make Express Payment", "", ""],

    # Button Titles
    "button_paybill"          => ["Pay Bill", "", ""],
    "button_zipmark"          => ["Pay Bill via Zipmark", "", ""],
    "button_easycart"         => ["Send To Shopping Cart", "", ""],
    "button_unconsolidate"    => ["Unconsolidate Bill", "", ""],
    "button_consolidate"      => ["Consolidate Bill", "", ""],
    "button_locateinvoice"    => ["Locate Invoice", "", ""],
    "button_editcontact"      => ["Edit Contact Profile", "", ""],
    "button_list_open"        => ["List Open/Unpaid Bills", "", ""],
    "button_list_expired"     => ["List Expired Bills", "", ""],
    "button_list_closed"      => ["List Closed Bills", "", ""],
    "button_list_paid"        => ["List Paid Bills", "", ""],
    "button_autopay"          => ["Auto-Pay Bills", "", ""],
    "button_view_contact"     => ["View Contact Profile", "", ""],
    "button_edit_contact"     => ["Edit Contact Profile", "", ""],
    "button_list_billing"     => ["List Billing Profiles", "", ""],
    "button_edit_billing"     => ["Edit Billing Profile", "", ""],
    "button_add_billing"      => ["Add Billing Profile", "", ""],
    "button_addalt_billing"   => ["Add Alternative Billing Profile", "", ""],
    "button_delete_billing"   => ["Delete Billing Profile", "", ""],
    "button_activate_billing" => ["Activate Billing Profile", "", ""],
    "button_activate_autopay" => ["Activate Auto-Payment", "", ""],
    "button_delete_autopay"   => ["Disable Auto-Payment", "", ""],
    "button_closewindow"      => ["Close Window", "", ""],
    "button_register"         => ["Register", "", ""],
    "button_datalink"         => ["Additional Information", "", ""],

    # Statements
    "statement_accepts"             => ["This merchant accepts:", "", ""],
    "statement_accepts2"            => ["This merchant only accepts the following cards/payment options:", "", ""],
    "statement_paymethod"           => ["Select Payment Method:", "", ""],
    "statement_invoice_expired"     => ["This invoice has expired.", "", ""],
    "statement_invoice_closed"      => ["This invoice was closed by the merchant.", "", ""],
    "statement_invoice_hidden"      => ["This invoice is not yet ready to be released.", "", ""],
    "statement_invoice_merged"      => ["This invoice was consolidated into another invoice by the merchant.", "", ""],
    "statement_invoice_paid"        => ["This invoice has already been paid.", "", ""],
    "statement_notfound"            => ["No Corresponding Invoice Found.", "", ""],
    "statement_notfound_query"      => ["Sorry no bills match your query...", "", ""],
    "statement_searchagain"         => ["Please ensure you entered the correct email address \& invoice number; then try again.", "", ""],
    "statement_srch_contactmerch"   => ["If you cannot locate a given invoice, please contact the merchant you are trying the pay, for payment assistance.", "", ""],
    "statement_merchassist1"        => ["Please contact", "", ""],
    "statement_merchassist2"        => ["directly, if you require assistance with this bill.", "", ""],
    "statement_nocontactinfo"       => ["No contact information on file.", "", ""],
    "statement_updatecontact"       => ["In order to proceed, please update your contact information.", "", ""],
    "statement_account_activate"    => ["Please confirm your email address \& activate your account.", "", ""],
    "statement_account_inactive"    => ["Your account is not active at this time.  Please contact <a href=\"mailto:billpaysupport\@plugnpay.com\">support</a> to reactivate your account.", "", ""],
    "statement_enter_profile"       => ["Please enter the profile information below.", "", ""],
    "statement_requiredfields"      => ["Required fields are marked with a", "", ""],
    "statement_contact_added"       => ["Your contact information has been added...", "", ""],
    "statement_contact_updated"     => ["Your contact information has been updated...", "", ""],
    "statement_nobillprofiles"      => ["No billing profiles available.", "", ""],
    "statement_nobillprofiles1"     => ["<b>NOTE:</b> You currently have no active billing profiles available.  You need to add a billing profile before you can pay any bills.", "", ""],
    "statement_nobillprofiles2"     => ["We highly recommend you add at least one billing profile to your account, before proceeding any further.", "", ""],
    "statement_nobillprofiles3"     => ["No matching active billing profiles available.", "", ""],
    "statement_add_billprof"        => ["You need to add/activate a billing profile before you can pay this bill.", "", ""],
    "statement_enter_ccach"         => ["Enter Credit Card or ACH Billing Information below.", "", ""],
    "statement_billing_added"       => ["The billing profile has been added...", "", ""],
    "statement_billing_updated"     => ["The billing profile has been updated...", "", ""],
    "statement_billing_deleted"     => ["The billing profile has been deleted...", "", ""],
    "statement_select_company"      => ["Select The Company You Wish To Auto-Pay:", "", ""],
    "statement_select_editprofile"  => ["Select Profile To Edit:", "", ""],
    "statement_select_delprofile"   => ["Select Profile To Delete:", "", ""],
    "statement_select_invoiceno"    => ["Click on the Invoice Number you wish to select.", "", ""],
    "statement_select_paymethod"    => ["Select Profile To Use For Payment:", "", ""],
    "statement_select_autopay"      => ["Select Auto-Payment Profile To Disable:", "", ""],
    "statement_consolidate"         => ["This invoice can be flagged for consolidation.", "", ""],
    "statement_consolidate_flag"    => ["This invoice was flagged for consolidation.", "", ""],
    "statement_consolidate_updated" => ["The invoice's consolidation status was updated.", "", ""],
    "statement_use_cc"              => ["Please use a credit card to pay this bill.", "", ""],
    "statement_usediff_cc"          => ["Please use a different card type to pay this bill.", "", ""],
    "statement_back_tryagain"       => ["Please use the back button \& try again.", "", ""],
    "statement_payment_success"     => ["Your payment was approved.", "", ""],
    "statement_payment_badcard"     => ["Your payment was declined.", "", ""],
    "statement_payment_problem"     => ["Your payment cannot be processed at this time.  Please try again later.", "", ""],
    "statement_payment_fraud"       => ["Your payment was declined.", "", ""],
    "statement_contact_support"     => ["Please <a href=\"mailto:billpaysupport\@plugnpay.com\">contact technical support</a> for assistance.", "", ""],
    "statement_noopenbills"         => ["No open bills available.", "", ""],
    "statement_nopayment"           => ["No Payment Is Due At This Time.", "", ""],
    "statement_autopay_usage"       => ["You can only activate automatic payment on an existing open bills.", "", ""],
    "statement_noautopay"           => ["No active auto-pay profiles available.", "", ""],
    "statement_autopay_added"       => ["The auto-pay profile has been added...", "", ""],
    "statement_autopay_updated"     => ["The auto-pay profile has been updated...", "", ""],
    "statement_autopay_deleted"     => ["The auto-pay profile has been deleted...", "", ""],
    "statement_printsave"           => ["Please print or save this as your receipt.", "", ""],
    "statement_merchant_support1"   => ["If you have a problem please email us at", "", ""],
    "statement_merchant_support2"   => ["Please give your full name, order ID number, and the exact nature of the problem.", "", ""],
    "statement_thankyou"            => ["Thank You For Your Payment", "", ""],

    "statement_terms_nbalance_plus" => ["By checking this box, you understand you owe nothing on this invoice, but wish to apply additional funds to the current balance.", "", ""],
    "statement_terms_pay"           => ["I agree to the Payment Terms \& Conditions.", "", ""],
    "statement_terms_service"       => ["I agree to the Terms of Service.", "", ""],
    "statement_terms_use"           => ["I agree to the Acceptable Use Policy.", "", ""],
    "statement_terms_privacy"       => ["I agree to the Privacy Policy.", "", ""],

    # Warning Messages
    "warn_consolidation"   => ["<font color=\"#ff0000\">WARNING:</font> <i>Consoldating an installment based invoice will result in you being required to pay the entire remaning balance of the invoice as a single payment.</i>", "", ""],
    "warn_achnote"         => ["<b>NOTE:</b> Fields are for data entry only.  Once entered, data is stored in credit card number field.", "", ""],
    "warn_openbills"       => ["<b>NOTE:</b> You have open/unpaid billings waiting.  If you would review/pay these bills now, please", "", ""],
    "warn_billing_deleted" => ["<b>NOTE:</b> All related auto-pay profiles, which used this billing profile, were also removed.", "", ""],

    # Error Messages
    "error_nomatch"            => ["Sorry no invoice matches the information provided.", "", ""],
    "error_require_email"      => ["<font color=\"#CC0000\" size=\"+1\">Email address required. Please try again.</font>", "", ""],
    "error_require_invoice_no" => ["<font color=\"#CC0000\" size=\"+1\">Invoice number required. Please try again.</font>", "", ""],
    "error_require_alias"      => ["<font color=\"#CC0000\" size=\"+1\">Alias Verification ID required. Please try again.</font>", "", ""],
    "error_require_account_no" => ["<font color=\"#CC0000\" size=\"+1\">Account Number required. Please try again.</font>", "", ""],
    "error_require_password"   => ["<font color=\"#CC0000\" size=\"+1\">Password required. Please try again.</font>", "", ""],
    "error_require_password2"  => ["<font color=\"#CC0000\" size=\"+1\">Confirm password required. Please try again.</font>", "", ""],
    "error_invalid_email"      => ["<font color=\"#CC0000\" size=\"+1\">Invalid email address. Please try again.</font>", "", ""],
    "error_invalid_invoice_no" => ["<font color=\"#CC0000\" size=\"+1\">Invalid invoice number. Please try again.</font>", "", ""],
    "error_invalid_cardnum"    => ["<font color=\"#FF0000\">ERROR: Invalid Card Number.  Please check and re-enter.</font>", "", ""],
    "error_invalid_accountnum" => ["<font color=\"#FF0000\">ERROR: Account Number has too few characters.</font>", "", ""],
    "error_invalid_routingnum" => ["<font color=\"#FF0000\">ERROR: Invalid Routing Number. Please check and re-enter.</font>", "", ""],
    "error_missing_required"   => ["<font color=\"#FF0000\">ERROR: Missing Required Information.  Please check and re-enter.</font>", "", ""],
    "error_mismatch_password"  => ["<font color=\"#CC0000\" size=\"+1\">Passwords do not match. Please try again.</font>", "", ""],
    "error_invalid_captcha"    => ["<font color=\"#FF0000\">ERROR: Invalid captcha response.  Please check and try again.</font>","",""],
    "error_card_onfile"        => ["<font color=\"#CC0000\" size=\"+1\">Card/Account number already on file. Please use a different number.</font>", "", ""],
    "error_merchant_inactive"  => ["Sorry, this merchant cannot accept online payments at this time.", "", ""],
    "error_merchant_noach"     => ["Sorry, this merchant does not accept online check payments at this time.", "", ""],
    "error_merchant_noaccept"  => ["Sorry, this merchant does not accept this card type at this time.", "", ""],
    "error_payment_min"        => ["Sorry, you must pay at least the minimum specified.", "", ""],
    "error_payment_max"        => ["Sorry, you can only pay as much as your current balance.", "", ""],
    "error_payment_unknown"    => ["<font color=\"#CC0000\" size=\"+1\">Error: Unknown payment response.</font>", "", ""],
    "error_registered"         => ["<font color=\"#CC0000\" size=\"+1\">Account already registered.  Please contact support for assistance.</font>", "", ""],
    "error_password_length"    => ["<font color=\"#CC0000\" size=\"+1\">Password must be at least 8 characters long. Please try again.</font>", "", ""],
    "error_password_noletters" => ["<font color=\"#CC0000\" size=\"+1\">Password must contain at least 1 letter. Please try again.</font>", "", ""],
    "error_password_nonumbers" => ["<font color=\"#CC0000\" size=\"+1\">Password must contain at least 1 number. Please try again.</font>", "", ""],
    "error_require_invoices"   => ["<font color=\"#CC0000\" size=\"+1\">Cannot find invoices which contain the information provided.<br>Only accounts with invoices on file may register.<br>Please check your information & try again.</font>", "", ""],
    "error_invalid_regcode"    => ["<font color=\"#CC0000\" size=\"+1\">Incorrect registration code. Please check your information \& try again.</font>", "", ""],

    "error_terms_nbalance_plus" => ["<font color=\"#CC0000\" size=\"+1\">You must agree to the negative balance statement.</font>", "", ""],
    "error_terms_pay"           => ["<font color=\"#CC0000\" size=\"+1\">You must agree to the Payment Terms \& Conditions.</font>", "", ""],
    "error_terms_service"       => ["<font color=\"#CC0000\" size=\"+1\">You must agree to the Terms of Service.</font>", "", ""],
    "error_terms_use"           => ["<font color=\"#CC0000\" size=\"+1\">You must agree to the Acceptable Use Policy.</font>", "", ""],
    "error_terms_privacy"       => ["<font color=\"#CC0000\" size=\"+1\">You must agree to the Privacy Policy.</font>", "", ""],

    # Customer Email Notice (Text Formatted Email)
    "emailcust_text_subject"        => ["Billing Presentment - [pnp_merch_company] - [pnp_invoice_no]", "", ""],
    "emailcust_text_new_invoice"    => ["A new or updated invoice has been inserted into Billing Presentment, which relates to your account.\nPlease refer to the attached invoiced bill.", "", ""],
    "emailcust_text_view_invoice"   => ["Once logged in, you may click on the following link to see the full invoice:", "", ""],
    "emailcust_text_free_signup"    => ["Don\'t have a Billing Presentment account yet, sign-up for FREE online:", "", ""],
    "emailcust_text_signup_reason"  => ["This free sign-up allows you to login, so you may review \& pay all invoiced bills you receive from [pnp_merch_company] online.", "", ""],
    "emailcust_text_expresspay"     => ["If you wish to make a one-time express payment, go to the below URL:", "", ""],
    "emailcust_text_contact_merch1" => ["If you have questions on this invoice, please contact the merchant noted above directly.", "", ""],
    "emailcust_text_contact_merch2" => ["If you have questions on this invoice, please contact us at \'[pnp_merch_pubemail]\'.", "", ""],
    "emailcust_text_thankyou"       => ["Thank you,\n[pnp_merch_company]\nSupport Staff", "", ""],

    # Customer Email Notice (HTML Formatted Email)
    "emailcust_html_subject"        => ["Billing Presentment - [pnp_merch_company] - [pnp_invoice_no]", "", ""],
    "emailcust_html_new_invoice"    => ["A new or updated invoice has been inserted into Billing Presentment, which relates to your account.<br>Please refer to the attached invoiced bill.", "", ""],
    "emailcust_html_view_invoice"   => ["Once logged in, you may click on the following link to see the full invoice:", "", ""],
    "emailcust_html_free_signup"    => ["Don\'t have a $billpay_language::lang_titles{'service_title'} account yet, sign-up for FREE online:", "", ""],
    "emailcust_html_signup_reason"  => ["This free sign-up allows you to login, so you may review \& pay all invoiced bills you receive from [pnp_merch_company] online.", "", ""],
    "emailcust_html_expresspay"     => ["If you wish to make a one-time express payment, click on the following link:", "", ""],
    "emailcust_html_contact_merch1" => ["If you have questions on this invoice, please contact the merchant noted above directly.", "", ""],
    "emailcust_html_contact_merch2" => ["If you have questions on this invoice, please contact us at \'[pnp_merch_pubemail]\'.", "", ""],
    "emailcust_html_thankyou"       => ["Thank you,<br>[pnp_merch_company]<br>Support Staff", "", ""],

    # Sign-up Form Specific Text
    "signup_text_welcome" => ["<font size=\"+1\">Thank you for taking a moment to register your Billing Presentment login.</font>", "", ""],
    "signup_text_intro1a" => ["<br>This free sign-up registration process will permit you to login to the Billing Presentment Administration area,", "", ""],
    "signup_text_intro1b" => ["<br>so you may review &amp; pay invoices you have received from participating companies.", "", ""],
    "signup_text_require" => ["<b>Please enter your email address \& the password you would like to use.</b><br>This information will be used to login to the Billing Presentment Administration area.", "", ""],
    "signup_text_email1a" => ["<br><b><i>&bull; If you have received the invoice via email, please enter the email address from your invoice.</i></b>\n", "", ""],
    "signup_text_email1b" => ["<br><b><i>&bull; If not, please enter the email address where you would like to receive them.</i></b>", "", ""],
    "signup_text_password1a" => ["<br><i>Minimum COMBINATION of 8 Letters and Numbers Required.</i>", "", ""],
    "signup_text_password1b" => ["<br>[NO Spaces or Non-Alphanumeric Characters Permitted.]", "", ""],
    "signup_text_noemail1a"  => ["<b>Please enter the Alias that appears on your acount \&amp; its assocated Account Number.</b>\n", "", ""],
    "signup_text_noemail1b"  => ["<br>This will be used to validate your registration \&amp; is required to activate your account.", "", ""],
    "signup_text_affirm1a" => ["<font size=\"+1\">Thank you for registering.</font>", "", ""],
    "signup_text_affirm1b" => ["You will receive an email shortly to confirm your email address \& activate your account.", "", ""],
    "signup_text_affirm1c" => ["<br>You will be unable to use your account, until you confirm your email address.", "", ""],
    "signup_text_affirm2a" => ["<font size=\"+1\">Thank you for confirming your registration.</font>\n", "", ""],
    "signup_text_affirm2b" => ["Your account has been activated, please <a href=\"/billpay/index.cgi\"><b>click here</b></a> to login and administer your account.", "", ""],
    "signup_text_affirm2c" => ["An activation confirmation email has been sent to ", "", ""],
  );

  ## Languange For Thank You Receipts
  %language::receipt_titles = (
    # Service Titles & Sub-Titles
    "service_title" => ["Order Receipt", "", ""],
    "service_title_return" => ["Return Receipt", "", ""],

    # Field Legends
    "legend_billing"        => ["Billing Address", "", ""],
    "legend_shipping"       => ["Shipping Addres", "", ""],
    "legend_invoiceinfo"    => ["Order Details", "", ""],
    "legend_paymentdetails" => ["Payment Details", "", ""],

    # Section Tables - Titles & Columns
    "section_productdetails" => ["Product Details", "", ""], 
    "section_cardholder"     => ["Card Holder Information:", "", ""],

    "column_item"    => ["Item \#", "", ""],
    "column_descr"   => ["Product Name", "", ""],
    "column_qty"     => ["Qty", "", ""],
    "column_cost"    => ["Unit Price", "", ""],
    "column_price"   => ["Price", "", ""],

    # Field Titles
    "date"           => ["Date:", "", ""],
    "orderid"        => ["Order ID:", "", ""],
    "morderid"       => ["Merchant ID:", "", ""],
    "subtotal"       => ["Subtotal: \&nbsp;", "", ""],
    "discount"       => ["Discount: \&nbsp;", "", ""],
    "shipping"       => ["Shipping: \&nbsp;", "", ""],
    "handling"       => ["Handling: \&nbsp;", "", ""],
    "tax"            => ["Sales Tax: \&nbsp;", "", ""],
    "total"          => ["Order Total: \&nbsp;", "", ""],
    "native_amt"     => ["Amount to be charged: \&nbsp;", "", ""],
    "gratuity"       => ["Gratuity: \&nbsp;", "", ""],
    "gratuity_total" => ["Total \+ Gratuity: \&nbsp;", "", ""],

    "card_name"      => ["Name:", "", ""],
    "card_fname"     => ["First Name:", "", ""],
    "card_lname"     => ["Last Name:", "", ""],
    "card_company"   => ["Company:", "", ""],
    "card_title"     => ["Title", "", ""],
    "card_address1"  => ["Billing Address:", "", ""],
    "card_address2"  => ["Line 2:", "", ""],
    "card_city"      => ["City:", "", ""],
    "card_state"     => ["State/Province:", "", ""],,
    "card_prov"      => ["International Province:", "", ""],
    "card_zip"       => ["ZipCode/Postal Code:", "", ""],
    "card_country"   => ["Country:", "", ""],

    "name"           => ["Name:", "", ""],
    "fname"          => ["First Name:", "", ""],
    "lname"          => ["Last Name:", "", ""],
    "company"        => ["Company:", "", ""],
    "title"          => ["Title", "", ""],
    "address1"       => ["Shipping Address", "", ""],
    "address2"       => ["Line 2", "", ""],
    "city"           => ["City", "", ""],
    "state"          => ["State/Province", "", ""],
    "province"       => ["International Province", "", ""],
    "zip"            => ["ZipCode/Postal Code", "", ""],
    "country"        => ["Country", "", ""],
    "phone"          => ["Phone:", "", ""],
    "fax"            => ["Fax:",   "", ""],
    "email"          => ["Email:", "", ""],

    "routingnum"     => ["Routing \#:", "", ""],
    "accountnum"     => ["Account \#:", "", ""],
    "card_number"    => ["Card \#:", "", ""],
    "card_exp"       => ["Card Exp:", "", ""],
    "card_type"      => ["Card Type:", "", ""],
    "authcode"       => ["Approval Code:", "", ""],
    "acct_code"      => ["Account Code:", "", ""],
    "acct_code2"     => ["Account Code2:", "", ""],
    "acct_code3"     => ["Account Code3:", "", ""],
    "acct_code4"     => ["Account Code4:", "", ""],
    "signature"      => ["<b>Signature:</b> ________________________________________", "", ""],
    "signature_pos"  => ["<b>X</b>__________________________________<br><font size=-1>Signature</font>", "", ""],

    # Hyperlink Titles
    "link_sitereturn" => ["CLICK HERE", "", ""],
    "link_siteshop"   => ["CLICK HERE", "", ""],

    # Button Titles
    "button_printpage"    => ["Print Page", "", ""],
    "button_printreceipt" => ["Print Receipt", "", ""],

    # Statements
    "statement_thankyou"    => ["Thank You For Your Order.", "", ""],
    "statement_printsave"   => ["Please print or save this as your receipt.", "", ""],
    "statement_merchant_support1" => ["If you have a problem please email us at ", "", ""],
    "statement_merchant_support2" => [".<br>Please give your full name, order ID number, and the exact nature of the problem.", "", ""],
    "statement_sitereturn"  => ["To return to site, ", "", ""],
    "statement_siteshop"    => ["To continue shopping, ", "", ""],
    "statement_sign"        => ["<font size=-1>By signing above, you (the card member) acknowledges receipt of goods and/or services in the amount of the total shown herein and agrees to perform the obligations set forth by the card member's agreement with the issuer.</font><p>Thank You", "", ""]
  );

