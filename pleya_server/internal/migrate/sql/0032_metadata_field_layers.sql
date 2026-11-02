-- Actuele bronwaarden voor veilige veldontgrendeling; geen historie of identiteit.
ALTER TABLE media_items ADD COLUMN metadata_field_layers jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata_field_layers) = 'object');
ALTER TABLE media_items ADD COLUMN metadata_nfo_safe boolean NOT NULL DEFAULT false;
