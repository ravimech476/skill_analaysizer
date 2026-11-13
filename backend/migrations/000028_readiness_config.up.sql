INSERT INTO app_config (key, value, description) VALUES
    ('readiness_weights',
     '{"cgpa": 0.25, "skills": 0.20, "aptitude": 0.15, "coding": 0.15, "attendance": 0.15, "communication": 0.10}',
     'Placement readiness score weights. Must sum to 1.0.')
ON CONFLICT (key) DO NOTHING;

INSERT INTO app_config (key, value, description) VALUES
    ('risk_thresholds',
     '{"high": 30, "medium": 50}',
     'Readiness score thresholds for risk levels. Below high = high risk, below medium = medium risk.')
ON CONFLICT (key) DO NOTHING;
