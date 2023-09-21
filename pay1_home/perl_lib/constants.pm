#!/usr/local/bin/perl

package constants;
require Exporter;

use strict;
use PlugNPay::Currency::LegacyHash::Tied;

our @ISA	= qw("Exporter");
our @EXPORT_OK	= qw(@months %cardlengths %timezones %daylighttimezones @standardfields %countries %USstates %USterritories %CNprovinces %USCNprov %UPSmethods %Ship_Methods %convert_countries %cvv_hash %avs_responses @planetpay_currencies @fifththird_currencies @ncb_currencies @pago_currencies @globalc_currencies @wirecard_currencies @visanet_currencies @fdmsintl_currencies @cccc_currencies);

# Processor Support Currencies

@constants::planetpay_currencies = ('aud','cad','eur','gbp','jpy','mxn','sgd');
@constants::fifththird_currencies = ('aud','cad','cny','eur','gbp','jpy','krw','mxn','usd');
@constants::ncb_currencies = ('ang','awg','bbd','bmd','bsd','bzd','cad','dop','eur','gbp','gyd','htg','jmd','kyd','ttd','usd','xcd');
@constants::pago_currencies = ('eur','gbp','usd');
@constants::globalc_currencies = ('eur','gbp','usd');
@constants::wirecard_currencies = ('eur','gbp','usd');
@constants::visanet_currencies = ('usd');
@constants::fdmsintl_currencies = ('ang','awg','bbd','bmd','bsd','bzd','cad','dop','eur','gbp','gyd','htg','jmd','kyd','ttd','usd','xcd');
@constants::cccc_currencies = ('ang','awg','bbd','bmd','bsd','bzd','cad','dop','eur','gbp','gyd','htg','jmd','kyd','ttd','usd','xcd');

# currencies, is actually an object using tie to load data from database;
our %currency_hash = ();
tie %currency_hash, 'PlugNPay::Currency::LegacyHash::Tied', { key => 'code', value => 'description' };

# months as an array
@constants::months = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');

# Allowed Card Lengths
%constants::cardlengths = ('VISA','13|16|19','MSTR','16','AMEX','15','DNRS','14','CRTB','14','DSCR','16','JCB','16','JAL','16','MYAR','16');

# CVV response code mappings
%constants::cvv_hash = ('M','Match','N','Did not match.','P','Not able to be processed.','U','Unavailable for checking.','X','Unavailable for checking.');

# AVS response codes
%constants::avs_responses = (
                    'Y',['5','Street and Postal Code match.'],
                    'X',['5','Exact Match - Address and Nine digit ZIP.'],
                    'D',['5','Street addresses and postal codes match for international transaction.'],
                    'F',['5','Street addresses & postal codes match for international transaction (UK only).'],
                    'M',['5','Street addresses and postal codes match for international transaction.'],
                    'A',['4','Address matches, ZIP does not.'],
                    'B',['4','Street addresses match for international transaction; postal code not verified.'],
                    'W',['3','Nine digit ZIP match, Address does not.'],
                    'Z',['3','Five digit ZIP matches, address does not.'],
                    'P',['3','Postal codes match for international transaction; street address not verified.'],
                    'E',['2','Address verification not allowed for card type.'],
                    'R',['2','Retry - System Unavailable.'],
                    'S',['2','Card Type Not Supported.'],
                    'U',['2','US Address Information Unavailable.'],
                    'G',['2','International Address Information Unavailable.'],
                    'C',['1','Street & postal code not verified for international transaction.'],
                    'I',['1','Address information not verified for international transaction.'],
                    'N',['0','Neither Address nor ZIP matches.'],
                  );

# timezones relative to GMT
# '-4','BST - Bermuda Standard Time GMT -4','-3','BDT - Bermuda Daylight Time GMT -3',
%constants::timezones = ('-12','IDLW - Intl Date Line West GMT -12','-11','NT - Nome Time GMT -11','-10',
'AHST - Alaska-Hawaii Standard Time GMT -10','-9','YST - Yukon Standard Time GMT -9','-8','PST - Pacific Standard Time GMT -8',
'-7','MST - Mountain Standard Time GMT -7','-6','CST - Central Standard Time GMT -6','-5','EST - Eastern Standard Time GMT -5',
'-4','AST - Atlantic Standard Time GMT -4','-3','ADT/Brasilia  GMT -3','-2','AT - Azores Time GMT -2',
'-1','WAT - West Africa Time GMT -1','0','GMT - Greenwich Mean Time','1','CET - Central European Time GMT +1',
'2','EET - Eastern European Time GMT +2','3','BT - Russia Zone 2 GMT +3','4','ZP4 - Russia Zone 3 GMT +4',
'5','ZP5 - Russia Zone 4 GMT +4','6','ZP6 - Russia Zone 5 GMT +6','7','ZP7 - Russia Zone 6 GMT +7',
'8','WAST - West Australian Standard Time GMT +8','9','JST - Japan Standard Time GMT +9',
'9.5','ACT - Australian Central Time GMT +9.5','10','EAST - East Australian Standard Time GMT +10','11','Solomon Is GMT +11',
'12','IDLE - International Date Line East GMT +12');

# timezones relative to GMT
# '-4','BST - Bermuda Standard Time GMT -4','-3','BDT - Bermuda Daylight Time GMT -3',
%constants::daylighttimezones = ('-12','IDLW - Intl Date Line West GMT -12','-11','NT - Nome Time GMT -11','-10',
'AHST - Alaska-Hawaii Standard Time GMT -10','-9','YST - Yukon Standard Time GMT -9','-8','PST - Pacific Standard Time GMT -8',
'-7','PDT/MST - Pacific Daylight/Mountain Standard Time GMT -7','-6','MDT - Mountain Daylight Time GMT -6','-5','CDT - Central Daylight Time GMT -5','-4','EDT - Eastern Daylight Time GMT -4',
'-3','ADT/Brasilia  GMT -3','-2','AT - Azores Time GMT -2',
'-1','WAT - West Africa Time GMT -1','0','GMT - Greenwich Mean Time','1','CET - Central European Time GMT +1',
'2','EET - Eastern European Time GMT +2','3','BT - Russia Zone 2 GMT +3','4','ZP4 - Russia Zone 3 GMT +4',
'5','ZP5 - Russia Zone 4 GMT +4','6','ZP6 - Russia Zone 5 GMT +6','7','ZP7 - Russia Zone 6 GMT +7',
'8','WAST - West Australian Standard Time GMT +8','9','JST - Japan Standard Time GMT +9',
'9.5','ACT - Australian Central Time GMT +9.5','10','EAST - East Australian Standard Time GMT +10','11','Solomon Is GMT +11',
'12','IDLE - International Date Line East GMT +12');

@constants::mster_tz_desc = ('IDLW','Intl Date Line West GMT -12','NT','Nome Time GMT -11','AHST','Alaska-Hawaii Standard Time GMT -10','YST','Yukon Standard Time GMT -9','PST','Pacific Standard Time GMT -8','PDT','Pacific Daylight Time GMT -7','MDT','Mountain Daylight Time GMT -6','CDT','Central Daylight Time GMT -5','EDT','Eastern Daylight Time GMT -4','ADT','Brasilia  GMT -3','AT','Azores Time GMT -2','WAT','West Africa Time GMT -1','GMT','Greenwich Mean Time','CET','Central European Time GMT +1','EET','Eastern European Time GMT +2','BT','Russia Zone 2 GMT +3','ZP4','Russia Zone 3 GMT +4','ZP5','Russia Zone 4 GMT +4','ZP6','Russia Zone 5 GMT +6','ZP7','Russia Zone 6 GMT +7','WAST','West Australian Standard Time GMT +8','JST','Japan Standard Time GMT +9','ACT','Australian Central Time GMT +9.5','EAST','East Australian Standard Time GMT +10','SOL','Solomon Is GMT +11','IDLE','International Date Line East GMT +12','PST','Pacific Standard Time GMT -8','MST','Mountain Standard Time GMT -7','CST','Central Standard Time GMT -6','EST','Eastern Standard Time GMT -5');

@constants::mster_tz_offset = ('IDLW','-12','NT','-11','AHST','-10','YST','-9','PST','-8','PDT','-7','MDT','-6','CDT','-5','EDT','-4','ADT','-3','AT','-2','WAT','-1','GMT','0','CET','1','EET','2','BT','3','ZP4','4','ZP5','5','ZP6','6','ZP7','7','WAST','8','JST','8.5','ACT','9','EAST','10','SOL','11','IDLE','12','PST','-8','MST','-7','CST','-6','EST','-5');

# default fields displayed on pay page
@constants::standardfields = ('card-name','card-address1','card-address2','card-city','card-state','card-zip','card-country',
                              'card-number','card-exp','card-type','phone','fax','email','uname','passwrd1','passwrd2',
                              'shipname','address1','address2','city','state','zip','country','card-prov','province',
                              'cookie_pw','ssnum','card-company','title','pinnumber','web900-pin'
                             );

# list retrieved from http://www.din.de/gremien/nas/nabd/iso3166ma/index.html
%constants::countries = (""," Select Your Country","AF","AFGHANISTAN","AL","ALBANIA","DZ","ALGERIA","AS","AMERICAN SAMOA","AD","ANDORRA",
                         "AO","ANGOLA","AI","ANGUILLA","AQ","ANTARCTICA","AG","ANTIGUA AND BARBUDA","AR","ARGENTINA",
                         "AM","ARMENIA","AW","ARUBA","AU","AUSTRALIA","AT","AUSTRIA","AZ","AZERBAIJAN","BS","BAHAMAS",
                         "BH","BAHRAIN","BD","BANGLADESH","BB","BARBADOS","BY","BELARUS","BE","BELGIUM","BZ","BELIZE",
                         "BJ","BENIN","BM","BERMUDA","BT","BHUTAN","BO","BOLIVIA","BA","BOSNIA AND HERZEGOVINA",
                         "BW","BOTSWANA","BV","BOUVET ISLAND","BR","BRAZIL","IO","BRITISH INDIAN OCEAN TERRITORY",
                         "BN","BRUNEI DARUSSALAM","BG","BULGARIA","BF","BURKINA FASO","BI","BURUNDI","KH","CAMBODIA",
                         "CM","CAMEROON","CA","CANADA","CV","CAPE VERDE","KY","CAYMAN ISLANDS","CF","CENTRAL AFRICAN REPUBLIC",
                         "TD","CHAD","CL","CHILE","CN","CHINA","CX","CHRISTMAS ISLAND","CC","COCOS (KEELING) ISLANDS",
                         "CO","COLOMBIA","KM","COMOROS","CG","CONGO","CD","CONGO, THE DEMOCRATIC REPUBLIC OF THE",
                         "CK","COOK ISLANDS","CR","COSTA RICA","CI","COTE D'IVOIRE","HR","CROATIA","CU","CUBA","CS","SERBIA AND MONTENEGRO",
                         "CY","CYPRUS","CZ","CZECH REPUBLIC","DK","DENMARK","DJ","DJIBOUTI","DM","DOMINICA",
                         "DO","DOMINICAN REPUBLIC","TP","EAST TIMOR","EC","ECUADOR","EG","EGYPT","SV","EL SALVADOR",
                         "GQ","EQUATORIAL GUINEA","ER","ERITREA","EE","ESTONIA","ET","ETHIOPIA","FK","FALKLAND ISLANDS (MALVINAS)",
                         "FO","FAROE ISLANDS","FJ","FIJI","FI","FINLAND","FR","FRANCE","GF","FRENCH GUIANA",
                         "PF","FRENCH POLYNESIA","TF","FRENCH SOUTHERN TERRITORIES","GA","GABON","GM","GAMBIA",
                         "GE","GEORGIA","DE","GERMANY","GH","GHANA","GI","GIBRALTAR","GR","GREECE","GL","GREENLAND",
                         "GD","GRENADA","GP","GUADELOUPE","GU","GUAM","GT","GUATEMALA","GN","GUINEA","GW","GUINEA-BISSAU",
                         "GY","GUYANA","HT","HAITI","HM","HEARD ISLAND AND MCDONALD ISLANDS","VA","HOLY SEE (VATICAN CITY STATE)",
                         "HN","HONDURAS","HK","HONG KONG","HU","HUNGARY","IS","ICELAND","IN","INDIA","ID","INDONESIA",
                         "IR","IRAN, ISLAMIC REPUBLIC OF","IQ","IRAQ","IE","IRELAND","IL","ISRAEL","IT","ITALY",
                         "JM","JAMAICA","JP","JAPAN","JO","JORDAN","KZ","KAZAKSTAN","KE","KENYA","KI","KIRIBATI",
                         "KP","KOREA, DEMOCRATIC PEOPLE'S REPUBLIC OF","KR","KOREA, REPUBLIC OF","KW","KUWAIT",
                         "KG","KYRGYZSTAN","LA","LAO PEOPLE'S DEMOCRATIC REPUBLIC","LV","LATVIA","LB","LEBANON",
                         "LS","LESOTHO","LR","LIBERIA","LY","LIBYAN ARAB JAMAHIRIYA","LI","LIECHTENSTEIN",
                         "LT","LITHUANIA","LU","LUXEMBOURG","ME","MONTENEGRO","MO","MACAU","MK","MACEDONIA, THE FORMER YUGOSLAV REPUBLIC OF",
                         "MG","MADAGASCAR","MW","MALAWI","MY","MALAYSIA","MV","MALDIVES","ML","MALI","MT","MALTA",
                         "MH","MARSHALL ISLANDS","MQ","MARTINIQUE","MR","MAURITANIA","MU","MAURITIUS","YT","MAYOTTE",
                         "MX","MEXICO","FM","MICRONESIA, FEDERATED STATES OF","MD","MOLDOVA, REPUBLIC OF",
                         "MC","MONACO","MN","MONGOLIA","MS","MONTSERRAT","MA","MOROCCO","MZ","MOZAMBIQUE",
                         "MM","MYANMAR","NA","NAMIBIA","NR","NAURU","NP","NEPAL","NL","NETHERLANDS","AN","NETHERLANDS ANTILLES",
                         "NC","NEW CALEDONIA","NZ","NEW ZEALAND","NI","NICARAGUA","NE","NIGER","NG","NIGERIA",
                         "NU","NIUE","NF","NORFOLK ISLAND","MP","NORTHERN MARIANA ISLANDS","NO","NORWAY",
                         "OM","OMAN","PK","PAKISTAN","PW","PALAU","PS","PALESTINIAN TERRITORY, OCCUPIED",
                         "PA","PANAMA","PG","PAPUA NEW GUINEA","PY","PARAGUAY","PE","PERU","PH","PHILIPPINES",
                         "PN","PITCAIRN","PL","POLAND","PT","PORTUGAL","PR","PUERTO RICO","QA","QATAR","RE","REUNION",
                         "RO","ROMANIA","RU","RUSSIAN FEDERATION","RS","SERBIA","RW","RWANDA","SH","SAINT HELENA","KN","SAINT KITTS AND NEVIS",
                         "LC","SAINT LUCIA","PM","SAINT PIERRE AND MIQUELON","VC","SAINT VINCENT AND THE GRENADINES",
                         "WS","SAMOA","SM","SAN MARINO","ST","SAO TOME AND PRINCIPE","SA","SAUDI ARABIA",
                         "SN","SENEGAL","SC","SEYCHELLES","SL","SIERRA LEONE","SG","SINGAPORE","SK","SLOVAKIA",
                         "SI","SLOVENIA","SB","SOLOMON ISLANDS","SO","SOMALIA","ZA","SOUTH AFRICA","GS","SOUTH GEORGIA AND THE SOUTH SANDWICH ISLANDS",
                         "ES","SPAIN","LK","SRI LANKA","SD","SUDAN","SR","SURINAME","SJ","SVALBARD AND JAN MAYEN",
                         "SZ","SWAZILAND","SE","SWEDEN","CH","SWITZERLAND","SY","SYRIAN ARAB REPUBLIC","TW","TAIWAN",
                         "TJ","TAJIKISTAN","TZ","TANZANIA, UNITED REPUBLIC OF","TH","THAILAND","TG","TOGO",
                         "TK","TOKELAU","TO","TONGA","TT","TRINIDAD AND TOBAGO","TN","TUNISIA","TR","TURKEY",
                         "TM","TURKMENISTAN","TC","TURKS AND CAICOS ISLANDS","TV","TUVALU","UG","UGANDA",
                         "UA","UKRAINE","AE","UNITED ARAB EMIRATES","GB","UNITED KINGDOM","US","UNITED STATES",
                         "UM","UNITED STATES MINOR OUTLYING ISLANDS","UY","URUGUAY","UZ","UZBEKISTAN","VU","VANUATU",
                         "VE","VENEZUELA","VN","VIET NAM","VG","VIRGIN ISLANDS, BRITISH","VI","VIRGIN ISLANDS, U.S.",
                         "WF","WALLIS AND FUTUNA","EH","WESTERN SAHARA","YE","YEMEN","ZM","ZAMBIA",
                         "ZW","ZIMBABWE");

# hash used to translate 3 character iso to 2 character iso uppercase
%constants::countries3to2 = ("abw","AW","afg","AF","ago","AO","aia","AI","alb","AL","and","AD","ant","AN","are","AE",
                             "arg","AR","arm","AM","asi","AP","asm","AS","ata","AQ","atf","TF","atg","AG","aus","AU",
                             "aut","AT","aze","AZ","bdi","BI","bel","BE","ben","BJ","bfa","BF","bgd","BD","bgr","BG",
                             "bhr","BH","bhs","BS","bih","BA","blr","BY","blz","BZ","bmu","BM","bol","BO","bra","BR",
                             "brb","BB","brn","BN","btn","BT","bvt","BV","bwa","BW","caf","CF","can","CA","cck","CC",
                             "che","CH","chl","CL","chn","CN","civ","CI","cmr","CM","cod","CD","cog","CG","cok","CK",
                             "col","CO","com","KM","cpv","CV","cri","CR","cub","CU","cxr","CX","cym","KY","cyp","CY",
                             "cze","CZ","deu","DE","dji","DJ","dma","DM","dnk","DK","dom","DO","dza","DZ","ecu","EC",
                             "egy","EG","eri","ER","esh","EH","esp","ES","est","EE","eth","ET","eur","EU","fin","FI",
                             "fji","FJ","flk","FK","fra","FR","fro","FO","fsm","FM","gab","GA","gbr","UK","geo","GE",
                             "gha","GH","gib","GI","gin","GN","glp","GP","gmb","GM","gnb","GW","gnq","GQ","grc","GR",
                             "grd","GD","grl","GL","gtm","GT","guf","GF","gum","GU","guy","GY","hkg","HK","hmd","HM",
                             "hnd","HN","hrv","HR","hti","HT","hun","HU","idn","ID","ind","IN","iot","IO","irl","IE",
                             "irn","IR","irq","IQ","isl","IS","isr","IL","ita","IT","jam","JM","jor","JO","jpn","JP",
                             "kaz","KZ","ken","KE","kgz","KG","khm","KH","kir","KI","kna","KN","kor","KR","kwt","KW",
                             "lao","LA","lbn","LB","lbr","LR","lby","LY","lca","LC","lie","LI","lka","LK","lso","LS",
                             "ltu","LT","lux","LU","lva","LV","mac","MO","mar","MA","mco","MC","mda","MD","mdg","MG",
                             "mne","ME","mdv","MV","mex","MX","mhl","MH","mkd","MK","mli","ML","mlt","MT","mmr","MM","mng","MN",
                             "mnp","MP","moz","MZ","mrt","MR","msr","MS","mtq","MQ","mus","MU","mwi","MW","mys","MY",
                             "myt","YT","nam","NA","ncl","NC","ner","NE","nfk","NF","nga","NG","nic","NI","niu","NU",
                             "nld","NL","nor","NO","npl","NP","nru","NR","nzl","NZ","omn","OM","pak","PK","pan","PA",
                             "pcn","PN","per","PE","phl","PH","plw","PW","png","PG","pol","PL","pri","PR","prk","KP",
                             "prt","PT","pry","PY","pse","PS","pyf","PF","qat","QA","reu","RE","rom","RO","rus","RU",
                             "rwa","RW","sau","SA","scg","CS","sdn","SD","sen","SN","sgp","SG","sgs","GS","shn","SH","sjm","SJ",
                             "slb","SB","sle","SL","slv","SV","smr","SM","som","SO","spm","PM","stp","ST","sur","SR","srb","RS",
                             "svk","SK","svn","SI","swe","SE","swz","SZ","syc","SC","syr","SY","tca","TC","tcd","TD",
                             "tgo","TG","tha","TH","tjk","TJ","tkl","TK","tkm","TM","tmp","TP","ton","TO","tto","TT",
                             "tun","TN","tur","TR","tuv","TV","twn","TW","tza","TZ","uga","UG","ukr","UA","umi","UM",
                             "ury","UY","usa","US","uzb","UZ","vat","VA","vct","VC","ven","VE","vgb","VG","vir","VI",
                             "vnm","VN","vut","VU","wlf","WF","wsm","WS","yem","YE","zaf","ZA","zmb","ZM",
                             "zwe","ZW");

# list of US states and abrevs
%constants::USstates = ("AL","Alabama","AK","Alaska","AZ","Arizona",
                        "AR","Arkansas","CA","California","CO","Colorado","CT","Connecticut","DE","Delaware",
                        "DC","District of Columbia","FL","Florida","GA","Georgia","HI","Hawaii","ID","Idaho",
                        "IL","Illinois","IN","Indiana","IA","Iowa","KS","Kansas","KY","Kentucky","LA","Louisiana",
                        "ME","Maine","MD","Maryland","MA","Massachusetts","MI","Michigan","MN","Minnesota","MS","Mississippi",
                        "MO","Missouri","MT","Montana","NE","Nebraska","NV","Nevada","NH","New Hampshire","NJ","New Jersey",
                        "NM","New Mexico","NY","New York","NC","North Carolina","ND","North Dakota","OH","Ohio","OK","Oklahoma",
                        "OR","Oregon","PA","Pennsylvania","PR","Puerto Rico",
                        "RI","Rhode Island","SC","South Carolina","SD","South Dakota","TN","Tennessee",
                        "TX","Texas","UT","Utah","VT","Vermont","VI","Virgin Islands","VA","Virginia","WA","Washington",
                        "WV","West Virginia","WI","Wisconsin","WY","Wyoming");

# list of US territories
%constants::USterritories  = ("AA","Armed Forces America","AE","Armed Forces Other Areas","AS","American Samoa",
                              "AP","Armed Forces Pacific","GU","Guam","MH","Marshall Islands","FM","Micronesia",
                              "MP","Northern Mariana Islands","PW","Palau");

# list of cancadian provinces
%constants::CNprovinces = ("ZZ","-- Country other than USA or Canada --","AB","Alberta","BC","British Columbia",
                           "NB","New Brunswick","MB","Manitoba","NL","Newfoundland and Labrador","NT","Northwest Territories","NS","Nova Scotia",
                           "NU","Nunavut","ON","Ontario","PE","Prince Edward Island","QC","Quebec","SK","Saskatchewan","YT","Yukon");

# I have no idea what this is used for :)
%constants::USCNprov = ("AB","Alberta","BC","British Columbia",
                        "NB","New Brunswick","MB","Manitoba","NF","Newfoundland","NT","Northwest Territories","NS","Nova Scotia",
                        "NU","Nunavut","ON","Ontario","PE","Prince Edward Island","QC","Quebec","SK","Saskatchewan","YT","Yukon");

# UPS shipping methods can eventually be removed
%constants::UPSmethods = ("ALL","All Servies","DOM","All Domestic Services","CAN","All Canadian Services","INT","All International Services",
                          "1DM","Next Day Air Early AM","1DMRS","Next Day Air Early AM Residential","1DA","Next Day Air",
                          "1DARS","Next Day Air Residential","1DP","Next Day Air Saver","1DPRS","Next Day Air Saver Residential",
                          "2DM","2nd Day Air A.M.","2DMRS","2nd Day Air A.M. Residential","2DA","2nd Day Air",
                          "2DARS","2nd Day Air Residential","3DS","3 Day Select","3DSRS","3 Day Select Residential",
                          "GND","Ground","GNDRES","Ground Residential","STD","Canada Standard",
                          "CXR","Worldwide Express to Canada","CXP","Worldwide Express Plus to Canada","CXD","Worldwide Expedited to Canada",
                          "XPR","Worldwide Express","XDM","Worldwide Express Plus","XPD","Worldwide Expedited");

# UPS and USPS shipping methods
%constants::Ship_Methods = ("ALL","UPS All Servies","DOM","UPS All Domestic Services","CAN","UPS All Canadian Services","INT","UPS All International Services",
                            "1DM","UPS Next Day Air Early AM","1DMRS","UPS Next Day Air Early AM Residential","1DA","UPS Next Day Air",
                            "1DARS","UPS Next Day Air Residential","1DP","UPS Next Day Air Saver","1DPRS","UPS Next Day Air Saver Residential",
                            "2DM","UPS 2nd Day Air A.M.","2DMRS","UPS 2nd Day Air A.M. Residential","2DA","UPS 2nd Day Air",
                            "2DARS","UPS 2nd Day Air Residential","3DS","UPS 3 Day Select","3DSRS","UPS 3 Day Select Residential",
                            "GND","UPS Ground","GNDRES","UPS Ground Residential","STD","UPS Canada Standard",
                            "CXR","UPS Worldwide Express to Canada","CXP","UPS Worldwide Express Plus to Canada","CXD","UPS Worldwide Expedited to Canada",
                            "XPR","UPS Worldwide Express","XDM","UPS Worldwide Express Plus","XPD","UPS Worldwide Expedited",
                            "Express","U.S. Postal Service Express","Priority","U.S. Postal Service Priority","Parcel","U.S. Postal Service Parcel");



# Country name to 2 Char. ISO
%constants::convert_countries = ("ANDORRA","AD","UNITED ARAB EMIRATES","AE","AFGHANISTAN","AF","ANTIGUA AND BARBUDA","AG",
          "ANGUILLA","AI","ALBANIA","AL","ARMENIA","AM","NETHERLANDS ANTILLES","AN","ANGOLA","AO","ANTARCTICA","AQ",
          "ARGENTINA","AR","AMERICAN SAMOA","AS","AUSTRIA","AT","AUSTRALIA","AU","ARUBA","AW","AZERBAIJAN","AZ",
          "BOSNIA AND HERZEGOVINA","BA","BARBADOS","BB","BANGLADESH","BD","BELGIUM","BE","BURKINA FASO","BF",
          "BULGARIA","BG","BAHRAIN","BH","BURUNDI","BI","BENIN","BJ","BERMUDA","BM","BRUNEI DARUSSALAM","BN",
          "BOLIVIA","BO","BRAZIL","BR","BAHAMAS","BS","BHUTAN","BT","BOUVET ISLAND","BV","BOTSWANA","BW",
          "BELARUS","BY","BELIZE","BZ","CANADA","CA","COCOS (KEELING) ISLANDS","CC","CONGO, THE DEMOCRATIC REPUBLIC OF THE","CD",
          "CENTRAL AFRICAN REPUBLIC","CF","CONGO","CG","SWITZERLAND","CH","COTE D'IVOIRE","CI","COOK ISLANDS","CK",
          "CHILE","CL","CAMEROON","CM","CHINA","CN","COLOMBIA","CO","COSTA RICA","CR","CUBA","CU","CAPE VERDE","CV",
          "CHRISTMAS ISLAND","CX","CYPRUS","CY","CZECH REPUBLIC","CZ","GERMANY","DE","DJIBOUTI","DJ","DENMARK","DK",
          "DOMINICA","DM","DOMINICAN REPUBLIC","DO","ALGERIA","DZ","ECUADOR","EC","ESTONIA","EE","EGYPT","EG",
          "WESTERN SAHARA","EH","ERITREA","ER","SPAIN","ES","ETHIOPIA","ET","FINLAND","FI","FIJI","FJ",
          "FALKLAND ISLANDS (MALVINAS)","FK","MICRONESIA, FEDERATED STATES OF","FM","FAROE ISLANDS","FO","FRANCE","FR",
          "GABON","GA","GRENADA","GD","GEORGIA","GE","FRENCH GUIANA","GF","GHANA","GH","GIBRALTAR","GI","GREENLAND","GL",
          "GAMBIA","GM","GUINEA","GN","GUADELOUPE","GP","EQUATORIAL GUINEA","GQ","GREECE","GR",
          "SOUTH GEORGIA AND THE SOUTH SANDWICH ISLANDS","GS","GUATEMALA","GT","GUAM","GU","GUINEA-BISSAU","GW",
          "GUYANA","GY","HONG KONG","HK","HEARD ISLAND AND MCDONALD ISLANDS","HM","HONDURAS","HN","CROATIA","HR",
          "HAITI","HT","HUNGARY","HU","INDONESIA","ID","IRELAND","IE","ISRAEL","IL","INDIA","IN",
          "BRITISH INDIAN OCEAN TERRITORY","IO","IRAQ","IQ","IRAN, ISLAMIC REPUBLIC OF","IR","ICELAND","IS",
          "ITALY","IT","JAMAICA","JM","JORDAN","JO","JAPAN","JP","KENYA","KE","KYRGYZSTAN","KG","CAMBODIA","KH",
          "KIRIBATI","KI","COMOROS","KM","SAINT KITTS AND NEVIS","KN","KOREA, DEMOCRATIC PEOPLE'S REPUBLIC OF","KP",
          "KOREA, REPUBLIC OF","KR","KUWAIT","KW","CAYMAN ISLANDS","KY","KAZAKSTAN","KZ","LAO PEOPLE'S DEMOCRATIC REPUBLIC","LA",
          "LEBANON","LB","SAINT LUCIA","LC","LIECHTENSTEIN","LI","SRI LANKA","LK","LIBERIA","LR","LESOTHO","LS","LITHUANIA","LT",
          "LUXEMBOURG","LU","LATVIA","LV","LIBYAN ARAB JAMAHIRIYA","LY","MOROCCO","MA","MONACO","MC","MOLDOVA, REPUBLIC OF","MD",
          "MADAGASCAR","ME","MONTENEGRO","MG","MARSHALL ISLANDS","MH","MACEDONIA, THE FORMER YUGOSLAV REPUBLIC OF","MK","MALI","ML","MYANMAR","MM",
          "MONGOLIA","MN","MACAU","MO","NORTHERN MARIANA ISLANDS","MP","MARTINIQUE","MQ","MAURITANIA","MR","MONTSERRAT","MS",
          "MALTA","MT","MAURITIUS","MU","MALDIVES","MV","MALAWI","MW","MEXICO","MX","MALAYSIA","MY","MOZAMBIQUE","MZ","NAMIBIA",
          "NA","NEW CALEDONIA","NC","NIGER","NE","NORFOLK ISLAND","NF","NIGERIA","NG","NICARAGUA","NI","NETHERLANDS","NL",
          "NORWAY","NO","NEPAL","NP","NAURU","NR","NIUE","NU","NEW ZEALAND","NZ","OMAN","OM","PANAMA","PA","PERU","PE",
          "FRENCH POLYNESIA","PF","PAPUA NEW GUINEA","PG","PHILIPPINES","PH","PAKISTAN","PK","POLAND","PL",
          "SAINT PIERRE AND MIQUELON","PM","PITCAIRN","PN","PUERTO RICO","PR","PALESTINIAN TERRITORY, OCCUPIED","PS",
          "PORTUGAL","PT","PALAU","PW","PARAGUAY","PY","QATAR","QA","REUNION","RE","ROMANIA","RO","RUSSIAN FEDERATION","RU",
          "RWANDA","RW","SAUDI ARABIA","SA","SOLOMON ISLANDS","SERBIA AND MONTENEGRO","CS","SERBIA","RS","SB","SEYCHELLES","SC","SUDAN","SD","SWEDEN","SE","SINGAPORE","SG",
          "SAINT HELENA","SH","SLOVENIA","SI","SVALBARD AND JAN MAYEN","SJ","SLOVAKIA","SK","SIERRA LEONE","SL","SAN MARINO","SM",
          "SENEGAL","SN","SOMALIA","SO","SURINAME","SR","SAO TOME AND PRINCIPE","ST","EL SALVADOR","SV","SYRIAN ARAB REPUBLIC","SY",
          "SWAZILAND","SZ","TURKS AND CAICOS ISLANDS","TC","CHAD","TD","FRENCH SOUTHERN TERRITORIES","TF","TOGO","TG",
          "THAILAND","TH","TAJIKISTAN","TJ","TOKELAU","TK","TURKMENISTAN","TM","TUNISIA","TN","TONGA","TO","EAST TIMOR","TP",
          "TURKEY","TR","TRINIDAD AND TOBAGO","TT","TUVALU","TV","TAIWAN, PROVINCE OF CHINA","TW","TANZANIA, UNITED REPUBLIC OF","TZ",
          "UKRAINE","UA","UGANDA","UG","UNITED KINGDOM","GB","UNITED STATES MINOR OUTLYING ISLANDS","UM","UNITED STATES","US",
          "U.S.A.","US","URUGUAY","UY","UZBEKISTAN","UZ","HOLY SEE (VATICAN CITY STATE)","VA","SAINT VINCENT AND THE GRENADINES","VC",
          "VENEZUELA","VE","VIRGIN ISLANDS, BRITISH","VG","VIRGIN ISLANDS, U.S.","VI","VIET NAM","VN","VANUATU","VU",
          "WALLIS AND FUTUNA","WF","SAMOA","WS","YEMEN","YE","MAYOTTE","YT","SOUTH AFRICA","ZA",
          "ZAMBIA","ZM","ZIMBABWE","ZW");



1;
