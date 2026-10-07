INSERT INTO app_config (key, value, description) VALUES
    ('global_mark_threshold',
     '{"default": 75, "skill_overrides": {}}',
     'Minimum mark percentage to auto-assign skills from subject-skill mappings. skill_overrides lets individual skills use a different threshold.')
ON CONFLICT (key) DO NOTHING;
