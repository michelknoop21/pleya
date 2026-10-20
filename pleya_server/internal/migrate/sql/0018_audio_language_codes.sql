-- 0018 taalcodes van sporen naar ISO 639-2/B (D1.8, S5-plan taak 2).
--
-- normalizeLanguage in ffprobe liet een terminologische code door ("nld"), waar
-- het contract de bibliografische belooft ("dut"). Een facet zou dezelfde taal
-- twee keer tonen en een filter op "dut" zou de helft missen. De omzettabel is
-- dezelfde als nameparse.iso6392tAliases.
--
-- Wat deze migratie niet kan herstellen: een tweeletterige tag ("nl") werd
-- eerder NULL en is niet terug te vinden; zo'n spoor krijgt zijn taal bij de
-- volgende probe van het bestand.
UPDATE media_streams SET language = CASE language
    WHEN 'nld' THEN 'dut' WHEN 'deu' THEN 'ger' WHEN 'fra' THEN 'fre' WHEN 'ces' THEN 'cze'
    WHEN 'ell' THEN 'gre' WHEN 'isl' THEN 'ice' WHEN 'ron' THEN 'rum' WHEN 'slk' THEN 'slo'
    WHEN 'zho' THEN 'chi' WHEN 'bod' THEN 'tib' WHEN 'cym' THEN 'wel' WHEN 'eus' THEN 'baq'
    WHEN 'fas' THEN 'per' WHEN 'hye' THEN 'arm' WHEN 'kat' THEN 'geo' WHEN 'mkd' THEN 'mac'
    WHEN 'mri' THEN 'mao' WHEN 'msa' THEN 'may' WHEN 'mya' THEN 'bur' WHEN 'sqi' THEN 'alb'
    ELSE language END
 WHERE language IN ('nld','deu','fra','ces','ell','isl','ron','slk','zho','bod','cym','eus',
                    'fas','hye','kat','mkd','mri','msa','mya','sqi');
