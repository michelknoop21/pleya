# Pleya Server — echte lokale image-terugval, 2 november 2026

Roadmap: A-07/server-gap-deployvoorbereiding. Geen productcodewrites; Unified-gedrag niet gewijzigd. Volledige logs/manifests uitsluitend onder `/tmp/task5-image-rollback-1102`.

**Vaste images, beide linux/amd64:** historisch `699026e1b031137fa79fd3639d49df58acc1d553` (schema30), `task5-rollback-old:1102`, image-ID `sha256:6729466e02db41be21cda54b253a123aff2925bced776c433edc2b5a4565803b`; huidig `44abf69f015bd0e639021f69fdac475522bcce12` (schema32), `task5-rollback-new:1102`, image-ID `sha256:e4c685ff3c793969fb115fa1564031475dce2b6bdb0453eb3629cd2984964a92`. Beide normaal gebouwd uit gitarchive + bijpassende Webbundel, gepinde Dockerfile, schone servercontext zonder .env; builds sequentieel via pleya-heavy, exit0. Revisielabels, bron/Web SHA256-manifests en buildlogs bewaard.

**Uitgevoerde procesketen, finale ronde exit0 (01:12:45–01:13:05 UTC):**
1. Echte schema30-image gereed; synthetische owner via auth/setup, aanvullende SQL-fixture: vier rollen, één bibliotheek/item, twee rechten en kijkstatussen, favoriet, waardering en instelling.
2. Normale `POST /pleya/v1/backups` →202/ok; schema30-manifest en archiefhash gecontroleerd. De configuratiegeheimen zitten versleuteld in `secrets.tar.enc` (de SQL-dump zelf blijft gzip, zoals het normale backupformaat).
3. Oude proces gestopt; schema32-image op dezelfde eigenDB/config gestart. Upgradeguard maakt eerst schema30-backup; vervolgens schema32 werkelijk gemigreerd en readyz200.
4. Schema32-proces gestopt; dezelfde schema30-image gestart: terminale exit78 met schema32/binary30-weigering. DB blijft32.
5. Schema32-image opnieuw gestart. Normale `POST /pleya/v1/backups/{id}/restore`, exacte API-confirmation →202, restore voltooid, terminale exit75; DB werkelijk30. Geen neerwaartse SQL of RunTo.
6. Exact dezelfde bewaarde schema30-image gestart →readyz200. Alle volledige rijdigests voor schema_migrations, server_instance, users, libraries, media_items, library_permissions, watch_states, favorites, ratings en server_settings exact gelijk; geen veldfilter. Signingkey-SHA256 exact gelijk. Daarna alleen eigen proces gestopt/verwijderd.

**Eerlijke meetgeschiedenis:** eerste guardassertion verwachtte foutief64; werkelijke veilige configexit78 is vastgelegd. Eerste terugkeer initialiseert alleen `media_items.sidecar_checked_at` van NULL naar een tijdstip; alle andere digests gelijk, restore vóór start volledig gelijk. Daarna gehele procesketen vanaf normaal geïnitialiseerde fixture herhaald; volledige vergelijking groen zonder uitzonderingen. Geen productpatch/guardversoepeling.

**Isolatie/cleanup:** UID/GID1000, read-only rootfs, cap-drop ALL/no-new-privileges, uitsluitend127.0.0.1:8873; eigen container `task5-imgrollback-server-1102`, DB `task5_imgrollback_1102`, rol `task5_imgrollback_role_1102` (geen superuser/createdb). Eigen container/DB/rol en mounts incl signing/configkeys/backuparchieven verwijderd; hashes en geredigeerde logs behouden; cleanup exit0. Op het cleanupmoment alle oorspronkelijke container-ID/naam/states onveranderd; geen extra containers waargenomen. Gecoördineerde metadatafixture8843/DBtask5_overrides_1102 niet aangeraakt; eventuele latere toevoeging valt buiten deze snapshot. Images behouden.

**Grenzen:** historisch afgeleide baseline, geen exact bekende NAS-productieimage (liveimage heeft geen revisionlabel). Geen NAS-, productie-, offsite-, hardware-, playback- of volledige-gapclaim. Geen resterende blocker voor deze lokale synthetische proces/image-terugval.

[Behouden bewijs en hashes](assets/2026-11-02-image-rollback/manifest.json). Volledige geredigeerde logs en het oorspronkelijke bewijsmanifest blijven in bovengenoemde tijdelijke bewijsmap.
