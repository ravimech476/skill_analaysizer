import { useState, useMemo } from 'react';
import { Alert, Button, Card, Divider, InputNumber, Slider, Space, Spin, Table, Typography, App } from 'antd';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api, errorMessage } from '../api/client';
import { SubjectSkillMapping } from '../components/SkillScoring';

const { Title, Text, Paragraph } = Typography;

interface ThresholdConfig {
  global_threshold: number;
  skill_overrides: Record<string, number>;
  match_weights: { skill: number; academic: number };
}

interface ReadinessWeights {
  cgpa: number;
  skills: number;
  aptitude: number;
  coding: number;
  attendance: number;
  communication: number;
}

interface RiskThresholds {
  high: number;
  medium: number;
}

interface ReadinessConfig {
  readiness_weights: ReadinessWeights;
  risk_thresholds: RiskThresholds;
}

async function getThreshold(): Promise<ThresholdConfig> {
  const r = await api.get('/config/threshold');
  return r.data.data;
}

async function saveThreshold(cfg: ThresholdConfig): Promise<ThresholdConfig> {
  const r = await api.put('/config/threshold', cfg);
  return r.data.data;
}

async function getReadiness(): Promise<ReadinessConfig> {
  const r = await api.get('/config/readiness');
  return r.data.data;
}

async function saveReadiness(cfg: { readiness_weights?: ReadinessWeights; risk_thresholds?: RiskThresholds }): Promise<ReadinessConfig> {
  const r = await api.put('/config/readiness', cfg);
  return r.data.data;
}

async function recompute(): Promise<{ recomputed: number }> {
  const r = await api.post('/skill-scores/recompute', { scope: 'all' });
  return r.data.data;
}

interface Skill {
  id: number;
  name: string;
  category: string;
}

async function getSkills(): Promise<Skill[]> {
  const r = await api.get('/skills', { params: { all: true } });
  return r.data.data;
}

const WEIGHT_LABELS: { key: keyof ReadinessWeights; label: string }[] = [
  { key: 'cgpa', label: 'CGPA' },
  { key: 'skills', label: 'Skills' },
  { key: 'aptitude', label: 'Aptitude' },
  { key: 'coding', label: 'Coding' },
  { key: 'attendance', label: 'Attendance' },
  { key: 'communication', label: 'Communication' },
];

const DEFAULT_WEIGHTS: ReadinessWeights = { cgpa: 0.25, skills: 0.20, aptitude: 0.15, coding: 0.15, attendance: 0.15, communication: 0.10 };
const DEFAULT_RISK: RiskThresholds = { high: 30, medium: 50 };

export default function ThresholdPage() {
  const { message } = App.useApp();
  const qc = useQueryClient();
  const { data: config, isLoading } = useQuery({ queryKey: ['threshold'], queryFn: getThreshold });
  const { data: skills } = useQuery({ queryKey: ['skills-all'], queryFn: getSkills });
  const { data: readinessConfig, isLoading: readinessLoading } = useQuery({ queryKey: ['readiness-config'], queryFn: getReadiness });

  const [globalThreshold, setGlobalThreshold] = useState<number | null>(null);
  const [overrides, setOverrides] = useState<Record<string, number> | null>(null);
  const [skillWeight, setSkillWeight] = useState<number | null>(null);

  // Readiness weights as percentages (0-100), stored as fractions (0-1) on the server
  const [rwEdits, setRwEdits] = useState<Partial<Record<keyof ReadinessWeights, number>> | null>(null);
  const [riskEdits, setRiskEdits] = useState<Partial<RiskThresholds> | null>(null);

  const gt = globalThreshold ?? config?.global_threshold ?? 75;
  const ov = overrides ?? config?.skill_overrides ?? {};
  const rawSw = config?.match_weights?.skill;
  const sw = skillWeight ?? (rawSw != null && rawSw <= 1 ? rawSw * 100 : rawSw ?? 70);

  // Readiness weights in percentage form for the UI
  const serverWeights = readinessConfig?.readiness_weights ?? DEFAULT_WEIGHTS;
  const rw = useMemo(() => {
    const base: Record<keyof ReadinessWeights, number> = {
      cgpa: Math.round(serverWeights.cgpa * 100),
      skills: Math.round(serverWeights.skills * 100),
      aptitude: Math.round(serverWeights.aptitude * 100),
      coding: Math.round(serverWeights.coding * 100),
      attendance: Math.round(serverWeights.attendance * 100),
      communication: Math.round(serverWeights.communication * 100),
    };
    if (rwEdits) return { ...base, ...rwEdits };
    return base;
  }, [serverWeights, rwEdits]);

  const rwTotal = WEIGHT_LABELS.reduce((sum, { key }) => sum + (rw[key] ?? 0), 0);

  const serverRisk = readinessConfig?.risk_thresholds ?? DEFAULT_RISK;
  const risk: RiskThresholds = {
    high: riskEdits?.high ?? serverRisk.high,
    medium: riskEdits?.medium ?? serverRisk.medium,
  };

  const saveMut = useMutation({
    mutationFn: () => saveThreshold({ global_threshold: gt, skill_overrides: ov, match_weights: { skill: sw / 100, academic: (100 - sw) / 100 } }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['threshold'] }); message.success('Saved'); },
    onError: (e) => message.error(errorMessage(e)),
  });

  const saveReadinessMut = useMutation({
    mutationFn: () => {
      const weights: ReadinessWeights = {
        cgpa: rw.cgpa / 100,
        skills: rw.skills / 100,
        aptitude: rw.aptitude / 100,
        coding: rw.coding / 100,
        attendance: rw.attendance / 100,
        communication: rw.communication / 100,
      };
      return saveReadiness({ readiness_weights: weights, risk_thresholds: risk });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['readiness-config'] });
      setRwEdits(null);
      setRiskEdits(null);
      message.success('Readiness configuration saved');
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  const recomputeMut = useMutation({
    mutationFn: recompute,
    onSuccess: (d) => message.success(`Recomputed ${d.recomputed} student scores`),
    onError: (e) => message.error(errorMessage(e)),
  });

  if (isLoading || readinessLoading) return <div style={{ textAlign: 'center', padding: 80 }}><Spin size="large" /></div>;

  const overrideData = (skills ?? []).map((s) => ({ key: s.id, name: s.name, category: s.category, threshold: ov[s.name] }));

  return (
    <div style={{ maxWidth: 800, margin: '0 auto' }}>
      <Card style={{ marginBottom: 16 }}>
        <Title level={5} style={{ marginTop: 0 }}>Readiness Score Weights</Title>
        <Paragraph type="secondary">
          How much each component contributes to a student's placement readiness score. Weights must sum to 100%.
        </Paragraph>
        {WEIGHT_LABELS.map(({ key, label }) => (
          <div key={key} style={{ display: 'flex', alignItems: 'center', marginBottom: 8, gap: 12 }}>
            <Text style={{ width: 120, flexShrink: 0 }}>{label}</Text>
            <Slider
              min={0} max={100} step={1}
              value={rw[key]}
              onChange={(v) => setRwEdits((prev) => ({ ...prev, [key]: v }))}
              style={{ flex: 1 }}
            />
            <InputNumber
              min={0} max={100} step={1}
              value={rw[key]}
              onChange={(v) => setRwEdits((prev) => ({ ...prev, [key]: v ?? 0 }))}
              addonAfter="%"
              style={{ width: 100 }}
            />
          </div>
        ))}
        <Divider style={{ margin: '12px 0' }} />
        <Text strong style={{ color: rwTotal === 100 ? undefined : 'var(--ant-color-error)' }}>
          Total: {rwTotal}%
        </Text>
        {rwTotal !== 100 && (
          <Alert type="warning" showIcon message={`Weights sum to ${rwTotal}%. Adjust them to total exactly 100%.`} style={{ marginTop: 8 }} />
        )}
      </Card>

      <Card style={{ marginBottom: 16 }}>
        <Title level={5} style={{ marginTop: 0 }}>Risk Thresholds</Title>
        <Paragraph type="secondary">
          Students with a readiness score below these thresholds are flagged as at-risk. The high-risk threshold must be below the medium-risk threshold.
        </Paragraph>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 8, gap: 12 }}>
          <Text style={{ width: 160, flexShrink: 0 }}>High risk below</Text>
          <Slider min={0} max={100} value={risk.high} onChange={(v) => setRiskEdits((prev) => ({ ...prev, high: v }))} style={{ flex: 1 }} />
          <InputNumber min={0} max={100} value={risk.high} onChange={(v) => setRiskEdits((prev) => ({ ...prev, high: v ?? 30 }))} addonAfter="%" style={{ width: 100 }} />
        </div>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 8, gap: 12 }}>
          <Text style={{ width: 160, flexShrink: 0 }}>Medium risk below</Text>
          <Slider min={0} max={100} value={risk.medium} onChange={(v) => setRiskEdits((prev) => ({ ...prev, medium: v }))} style={{ flex: 1 }} />
          <InputNumber min={0} max={100} value={risk.medium} onChange={(v) => setRiskEdits((prev) => ({ ...prev, medium: v ?? 50 }))} addonAfter="%" style={{ width: 100 }} />
        </div>
        {risk.high >= risk.medium && (
          <Alert type="error" showIcon message="High-risk threshold must be below medium-risk threshold." style={{ marginTop: 8 }} />
        )}
      </Card>

      <Space style={{ marginBottom: 16 }}>
        <Button
          type="primary"
          loading={saveReadinessMut.isPending}
          disabled={rwTotal !== 100 || risk.high >= risk.medium}
          onClick={() => saveReadinessMut.mutate()}
        >
          Save Readiness Config
        </Button>
      </Space>

      <Divider />

      <Card style={{ marginBottom: 16 }}>
        <Title level={5} style={{ marginTop: 0 }}>Global Mark Threshold</Title>
        <Paragraph type="secondary">
          Minimum mark percentage to consider a student skilled in a subject's mapped skills.
          If a student scores above this threshold in a subject, they automatically get the skills mapped to that subject.
        </Paragraph>
        <Space align="center" style={{ width: '100%' }}>
          <Slider min={0} max={100} value={gt} onChange={setGlobalThreshold} style={{ width: 400 }} />
          <InputNumber min={0} max={100} value={gt} onChange={(v) => setGlobalThreshold(v ?? 75)} addonAfter="%" />
        </Space>
      </Card>

      <Card style={{ marginBottom: 16 }}>
        <Title level={5} style={{ marginTop: 0 }}>Per-Skill Threshold Override</Title>
        <Paragraph type="secondary">
          Override the global threshold for specific skills. Leave blank to use the global value ({gt}%).
        </Paragraph>
        <Table
          dataSource={overrideData}
          pagination={false}
          size="small"
          columns={[
            { title: 'Skill', dataIndex: 'name', key: 'name' },
            { title: 'Category', dataIndex: 'category', key: 'category' },
            {
              title: 'Override %',
              key: 'threshold',
              width: 140,
              render: (_, row) => (
                <InputNumber
                  min={0} max={100}
                  placeholder={`${gt}`}
                  value={row.threshold}
                  onChange={(v) => {
                    const next = { ...ov };
                    if (v == null) { delete next[row.name]; } else { next[row.name] = v; }
                    setOverrides(next);
                  }}
                  style={{ width: 110 }}
                />
              ),
            },
          ]}
        />
      </Card>

      <Card style={{ marginBottom: 16 }}>
        <Title level={5} style={{ marginTop: 0 }}>Match Weights</Title>
        <Paragraph type="secondary">
          When matching students to placement drives, how much weight to give skill scores vs academic scores (CGPA).
        </Paragraph>
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text>Skill Score: {sw}%</Text>
          <Slider min={0} max={100} value={sw} onChange={setSkillWeight} />
          <Text>Academic Score: {100 - sw}%</Text>
        </Space>
      </Card>

      <Space style={{ marginBottom: 16 }}>
        <Button type="primary" loading={saveMut.isPending} onClick={() => saveMut.mutate()}>
          Save Skill Configuration
        </Button>
        <Button loading={recomputeMut.isPending} onClick={() => recomputeMut.mutate()}>
          Recompute All Student Skills
        </Button>
      </Space>

      <Card style={{ marginBottom: 16 }}>
        <Title level={5} style={{ marginTop: 0 }}>Skills each subject builds</Title>
        <SubjectSkillMapping />
      </Card>
    </div>
  );
}
