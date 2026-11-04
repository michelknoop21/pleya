# Web: transparante P-markeringen

Roadmap: C-05 / S8. Unified impact: alleen afgeleide Web-merkassets; navigatie, rechten en playback blijven gelijk.

Michel meldde zwarte achtergronden rond de Web-logo’s. De kleine P-bestanden van 64 en 256 pixels hadden volledig ondoorzichtige canvassen (#0B0B0B); de tweelaagse woordmerken waren al transparant. De gedeelde merkgenerator maakt de twee Web-markeringen nu met transparant canvas. Beide PNG’s zijn opnieuw gegenereerd, zonder wijzigingen aan andere platformassets.

Bewijs: beide bestanden gebruiken alpha 0–255 en hebben vier transparante hoeken; dezelfde controle faalt op beide oorspronkelijke HEAD-assets. De vijf bestaande Wordmark/ConsumerSidebar-tests slagen. Browsercontrole gebruikt uitsluitend lokale routes met synthetische catalogus, controleert de gedecodeerde beeldalpha en legt de compacte en uitgeklapte Home-sidebar vast. Bewijsbestanden: `review/web-marks-pixels.log`, `web-marks-tests.log`, `web-marks-browser.log`, `web-marks-home.png`, `web-marks-home-expanded.png` in het taakwerkgebied buiten deze repository.

Release: onafhankelijke review, normale checks/CI en NAS-uitrol volgen de bestaande releaseprocedure. Deze correctie sluit het afzonderlijke macOS-toegankelijkheidsonderzoek of TestFlight niet af.
