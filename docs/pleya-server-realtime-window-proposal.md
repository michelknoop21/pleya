# Voorstel: begrensd realtimevenster

Roadmap C-05/S21. Status: voorstel, nog geen contractvrijgave. Dit werkt uitsluitend het bestaande J.5c-venster en hoofdstuk 14 van de serverarchitectuur uit.

Open alleen `GET /pleya/v1/events` als WebSocket, buiten OpenAPI. Authenticatie gebeurt met het eerste bericht `{token}`, nooit met een token in de URL. Daarna volgen `{seq, type, payload}` en hervatten via `?since=`. De bestaande optionele capability `realtime` meldt beschikbaarheid; ontbrekend blijft false. Bestaande REST-operaties en foutcodes veranderen niet.

De server levert wijzigingssignalen voor scans, taken en persoonlijke staat. Elk signaal wordt vóór verzending getoetst aan de actuele gebruikersrechten. Een ingetrokken sessie of bibliotheektoegang stopt verdere aflevering. Signalen dragen verwijzingen naar bestaande resources, geen volledige documenten of geheimen.

Een onderbroken client haalt beschikbare gemiste signalen op. Wanneer herstel vanaf het opgegeven volgnummer niet kan, bijvoorbeeld na herstart of verlopen bewaring, volgt een expliciet ververssignaal en leest de client de actuele API-staat opnieuw. Er ontstaat geen nieuwe bron van kijkstatus. Herverbinden gebruikt begrensde vertraging; polling blijft werken als de verbinding ontbreekt of geweigerd wordt.

Bijbehorende protocoltekst, voorbeeldberichten, Web- en Dartparsers mogen binnen dit venster veranderen. De REST-types blijven gelijk. De zes compatibiliteitsregels gelden: uitsluitend additief binnen major 1, optionele capability, gesloten nieuwe berichtvormen, veilige defaults, gelijkgezette fixtures en geen stil veranderde betekenis van bestaande velden.

Sluiten vereist gerichte replay-/reconnecttests, rechtenintrekking tijdens een open verbinding, twee gebruikers zonder kruisende persoonlijke events en een bewezen pollingterugval. Webacceptatie krijgt echte screenshots en toetsenbordcontrole. Onafhankelijke review en de bestaande gates blijven verplicht. NAS-proxyacceptatie en fysieke apparaten blijven afzonderlijke bewijsstappen. Geen publicatievrijgave.
