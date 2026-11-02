# Pleya Server schema33 — normale lokale image/runtime, 2 november 2026

**PASS.** Roadmap A-07/C-05 server-gapverificatie; geen product-/Go-/authoritywrites of commit. Unified-impact: bestaande server-API met echte image getoetst; geen clientwijziging.

**Vaste bron/buildgrens:** `316e8510a7e2fc45117551991f0b3c4fbeabf7d8`, exact gitarchive van server/Web/contract. Bijpassende Webbundel via normale build-into-server/check-api-types; dezelfde bun.lock gecontroleerd, bestaande dependencies gebruikt. Normale gepinde Dockerfile, schone servercontext zonder .env/cachegeheimen. Webselector die apart loopt is niet meegenomen. Eén build, geen nieuwe SDK/toolchain/imagebasis. Bron/Web SHA256-manifest bewaard.

**Image:** `task5-schema33:1102`, `sha256:ef4a7c7548374d5e8365ba3d0d30f8297600f450f1071c52cbb50d76e743f758`, linux/amd64; revisielabel exact316e8510. desktop-linux,4CPU/~8GB; vooraf9GB VMvrij en121GB hostvrij. Alle zware build/runtimeacties sequentieel via pleya-heavy; geen restart/prune of andere DB-reset.

| Echte controle | Resultaat |
|---|---|
| Normale Web-/imagebuild | exit0/0; buildlogs en image-inspect bewaard |
| Proces en grenzen | UID/GID1000; read-only rootfs; cap-drop ALL/no-new-privileges; eigen mounts/media readonly; alleen127.0.0.1:8873 |
| Gezondheid/auth/caps | healthz/readyz200, binary-healthcheck0, libraries zonder token401; keyless metadata_search=false/artwork_choices=true |
| Verse migratie en scan | schema max33/count33; echte1s160×90clip met ffmpeg uit dezelfde image, lokale synthetische PNG;1item,1mediafile+1artworkfile; scan succeeded |
| Pinselectie en levering | echte owner via auth/setup200; GET artwork-candidates lokale beschikbare poster; PUT artwork200; levering200 |
| Cacheverlies | alleen eigen cache/artwork-pins verwijderd; nieuwe GET200 herbouwt cache uit lokale readonlybron; SHA256 en ETag exact gelijk |
| Herstart eigen container | tweede startupscan succeeded; schema33 en alle server/library/item/file/pin-IDs exact behouden; artwork-SHA/ETag gelijk |

Runtime-script exit0; clipgeneratie exit0; cleanup exit0. Geen configuratie-/guard-/productpatch nodig. Pin-SHA256 `41313a9a2e0164570d324a4302cf721a3fb4ef48287f101b1f6dcffef9691040`; details in pin-proof.json en ids-before/after.txt.

**Isolatie/cleanup:** eigen container`task5-schema33-server-1102`, DB`task5_schema33_1102`, rol`task5_schema33_role_1102`, netwerk`task5-schema33-network-1102` verwijderd. Eigen media/config/cache/transcode/backups incl signingkeys verwijderd; nieuwe image behouden. Voor PG-bereikbaarheid hing alleen de eigen server ook aan het bestaande netwerk; geen PG-netwerkwijziging. Alle oorspronkelijke container-ID/naam/states onveranderd; beschermde PG283651dc… en netwerk7ffb9f7b… hebben exact oorspronkelijkeIDs;30/31/32images behouden. Geen nieuwe containers in voor-/na-vergelijking; andere workers onaangeroerd. Logs geredigeerd, hashes/manifests buiten trackedsource.

**Niet bewezen:**33-upgrade van bestaandeDB, versleutelde33backup/restore,33→30rollback, bronverlies/gewijzigdebron/concurrente pins, remote-provider/TMDBselectie, browser-Webselector, echte gebruikersmedia/playback, NAS/productie/hardware. Eerdere encrypted33restoretests blijven afzonderlijk bronbewijs; eerdere30/32-imageproeven zijn geen33rollbackbewijs. Geen resterende blocker voor deze begrensde fresh33-runtimeproef.

Volledig lokaal bewijs: [/tmp/task5-image-schema33-1102/evidence-manifest.json](/tmp/task5-image-schema33-1102/evidence-manifest.json), met bron-/Webmanifest en afzonderlijke build/runtime/cleanup-exits. Geen bewijsbestanden of runtimegeheimen in de productimage toegevoegd.
