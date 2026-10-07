import { useState } from 'react';
import { Button, Card, InputNumber, Slider, Space, Spin, Table, Typography, App } from 'antd';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api, errorMessage } from '../api/client';

const { Title, Text, Paragraph } = Typography;

interface ThresholdConfig {
  global_threshold: number;
  skill_overrides: Record<string, number>;
  match_weights: { skill: number; academic: number };
}

async function getThreshold(): Promise<ThresholdConfig> {
  const r = await api.get('/config/threshold');
  return r.data.data;
}

async function saveThreshold(cfg: ThresholdConfig): Promise<ThresholdConfig> {
  const r = await api.put('/config/threshold', cfg);
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

export default function ThresholdPage() {
  const { message } = App.useApp();
  const qc = useQueryClient();
  const { data: config, isLoading } = useQuery({ queryKey: ['threshold'], queryFn: getThreshold });
  const { data: skills } = useQuery({ queryKey: ['skills-all'], queryFn: getSkills });

  const [globalThreshold, setGlobalThreshold] = useState<number | null>(null);
  const [overrides, setOverrides] = useState<Record<string, number> | null>(null);
  const [skillWeight, setSkillWeight] = useState<number | null>(null);

  const gt = globalThreshold ?? config?.global_threshold ?? 75;
  const ov = overrides ?? config?.skill_overrides ?? {};
  const sw = skillWeight ?? config?.match_weights?.skill ?? 70;

  const saveMut = useMutation({
    mutationFn: () => saveThreshold({ global_threshold: gt, skill_overrides: ov, match_weights: { skill: sw, academic: 100 - sw } }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['threshold'] }); message.success('Saved'); },
    onError: (e) => message.error(errorMessage(e)),
  });

  const recomputeMut = useMutation({
    mutationFn: recompute,
    onSuccess: (d) => message.success(`Recomputed ${d.recomputed} student scores`),
    onError: (e) => message.error(errorMessage(e)),
  });

  if (isLoading) return <div style={{ textAlign: 'center', padding: 80 }}><Spin size="large" /></div>;

  const overrideData = (skills ?? []).map((s) => ({ key: s.id, name: s.name, category: s.category, threshold: ov[s.name] }));

  return (
    <div style={{ maxWidth: 800, margin: '0 auto' }}>
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

      <Space>
        <Button type="primary" loading={saveMut.isPending} onClick={() => saveMut.mutate()}>
          Save Configuration
        </Button>
        <Button loading={recomputeMut.isPending} onClick={() => recomputeMut.mutate()}>
          Recompute All Student Skills
        </Button>
      </Space>
    </div>
  );
}
