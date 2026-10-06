import { useState } from 'react';
import { Button, Card, Drawer, Empty, Input, Modal, Rate, Select, Space, Spin, Table, Tabs, Tag, Tooltip, Typography, message } from 'antd';
import { CheckCircleTwoTone, PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import { placementApi, pretty, type Skill, type StudentSkill } from '../api/placement';
import { scoresApi } from '../api/careers';
import { studentsApi } from '../api/phase2';
import { useClasses } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import MasterCrud from '../components/MasterCrud';
import { ScoreBadge, ScoringWeights, SubjectSkillMapping, useSkillScores } from '../components/SkillScoring';
import type { FileLink, UploadedFile } from '../api/files';
import { FileAnchor, UploadButton } from '../components/Files';

const CATEGORIES = ['programming', 'framework', 'database', 'tool', 'technical', 'soft_skill', 'domain'].map((c) => ({ value: c, label: pretty(c) }));
const SOURCES = ['assessment', 'certification', 'project', 'internship', 'course'].map((s) => ({ value: s, label: pretty(s) }));
const CATEGORY_COLORS: Record<string, string> = { programming: 'blue', framework: 'geekblue', database: 'cyan', tool: 'purple', technical: 'volcano', soft_skill: 'green', domain: 'gold' };
export const LEVELS = ['', 'Beginner', 'Basic', 'Intermediate', 'Advanced', 'Expert'];

export function useSkills() {
  return useQuery({ queryKey: ['lookup', 'skills'], queryFn: placementApi.skills, staleTime: 5 * 60_000 });
}

/** A student's skills; editable by staff/admin (students and parents only read). */
export function StudentSkillsEditor({ studentId }: { studentId: number }) {
  const { can, user } = useAuth();
  const qc = useQueryClient();
  const { data: all } = useSkills();
  const { data: list, isLoading } = useQuery({ queryKey: ['student-skills', studentId], queryFn: () => placementApi.studentSkills(studentId) });
  const [editing, setEditing] = useState<{
    skill_id?: number;
    proficiency: number;
    source: string;
    remarks?: string | null;
    certificate?: FileLink | null; // currently on file
    newCert?: UploadedFile; // uploaded in this dialog
    removeCert?: boolean;
  } | null>(null);
  const staff = ['student', 'parent'].indexOf(audienceOf(user?.roles ?? [])) < 0;
  const canEdit = staff && can('student_skill.create', 'student_skill.update');

  const { data: scores } = useSkillScores(studentId);
  const scoreOf = (skillId: number) => scores?.scores.find((s) => s.skill_id === skillId);

  // Every write below moves the blended score, the rankings built on it and the career matches.
  const reload = () => {
    qc.invalidateQueries({ queryKey: ['skill-matrix'] });
    qc.invalidateQueries({ queryKey: ['skill-scores', studentId] });
    qc.invalidateQueries({ queryKey: ['career-matches', studentId] });
  };
  const refresh = (l: StudentSkill[]) => {
    qc.setQueryData(['student-skills', studentId], l);
    reload();
  };
  const save = useMutation({
    mutationFn: () =>
      placementApi.saveStudentSkill(studentId, {
        skill_id: editing!.skill_id!,
        proficiency: editing!.proficiency,
        source: editing!.source,
        remarks: editing!.remarks,
        certificate_file_id: editing!.newCert?.id,
        remove_certificate: !editing!.newCert && editing!.removeCert,
      }),
    onSuccess: (l) => {
      refresh(l);
      message.success('Skill saved');
      setEditing(null);
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const remove = useMutation({
    mutationFn: (skillId: number) => placementApi.removeStudentSkill(studentId, skillId),
    onSuccess: refresh,
    onError: (e) => message.error(errorMessage(e)),
  });
  const verify = useMutation({
    mutationFn: (v: { skillId: number; verified: boolean }) => scoresApi.verifyCertificate(studentId, v.skillId, v.verified),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['student-skills', studentId] });
      reload();
      message.success('Certificate updated');
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  if (isLoading) return <Spin />;
  return (
    <>
      <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }}>
        <Typography.Text type="secondary">
          {list?.length ?? 0} skills recorded
          {scores?.computed_at ? ` · scores worked out ${dayjs(scores.computed_at).format('DD MMM, HH:mm')}` : ''}
        </Typography.Text>
        {canEdit && (
          <Button size="small" icon={<PlusOutlined />} onClick={() => setEditing({ proficiency: 3, source: 'assessment' })}>
            Add skill
          </Button>
        )}
      </Space>
      <Table<StudentSkill>
        rowKey="skill_id"
        size="small"
        pagination={false}
        dataSource={list}
        locale={{ emptyText: 'No skills recorded yet' }}
        scroll={{ x: 820 }}
        columns={[
          { title: 'Skill', render: (_, s) => <Space>{s.name}<Tag color={CATEGORY_COLORS[s.category]}>{pretty(s.category)}</Tag></Space> },
          { title: 'Level', width: 170, render: (_, s) => <Tooltip title={LEVELS[s.proficiency]}><Rate disabled count={5} value={s.proficiency} style={{ fontSize: 14 }} /></Tooltip> },
          {
            // The blended score: the recorded level plus certificates, assessments and marks.
            title: 'Score',
            width: 80,
            align: 'right',
            render: (_, s) => <ScoreBadge row={scoreOf(s.skill_id)} />,
          },
          { title: 'Source', dataIndex: 'source', width: 120, render: (v) => pretty(v) },
          {
            title: 'Certificate',
            width: 190,
            render: (_, s) => (
              <Space size={4} wrap>
                {s.certificate ? <FileAnchor link={s.certificate} label="View" /> : s.certificate_url ? (
                  <a href={s.certificate_url} target="_blank" rel="noreferrer">Link</a>
                ) : (
                  <Typography.Text type="secondary">—</Typography.Text>
                )}
                {s.certificate_verified && (
                  <Tooltip title={`Verified by ${s.certificate_verified_by ?? 'staff'}${s.certificate_verified_at ? ` on ${dayjs(s.certificate_verified_at).format('DD MMM YY')}` : ''}`}>
                    <CheckCircleTwoTone twoToneColor="#15803d" />
                  </Tooltip>
                )}
                {canEdit && (s.certificate || s.certificate_url) && (
                  <Button size="small" type="link" loading={verify.isPending} onClick={() => verify.mutate({ skillId: s.skill_id, verified: !s.certificate_verified })}>
                    {s.certificate_verified ? 'Unverify' : 'Verify'}
                  </Button>
                )}
              </Space>
            ),
          },
          { title: 'Recorded', width: 170, render: (_, s) => <Typography.Text type="secondary">{s.recorded_by ?? '—'} · {dayjs(s.updated_at).format('DD MMM YY')}</Typography.Text> },
          ...(canEdit
            ? [{
                title: '',
                key: 'x',
                width: 130,
                render: (_: unknown, s: StudentSkill) => (
                  <Space>
                    <Button size="small" onClick={() => setEditing({ skill_id: s.skill_id, proficiency: s.proficiency, source: s.source, remarks: s.remarks, certificate: s.certificate })}>Edit</Button>
                    {can('student_skill.delete') && <Button size="small" danger onClick={() => Modal.confirm({ title: `Remove ${s.name}?`, onOk: () => remove.mutateAsync(s.skill_id) })}>✕</Button>}
                  </Space>
                ),
              }]
            : []),
        ]}
      />
      {canEdit && (
        <Typography.Paragraph type="secondary" style={{ marginTop: 8, marginBottom: 0, fontSize: 12 }}>
          A score blends the level recorded here with verified certificates, assessment results and marks in subjects
          mapped to the skill. Hover a score to see what went into it.
        </Typography.Paragraph>
      )}
      <Modal title="Record skill" open={!!editing} onCancel={() => setEditing(null)} onOk={() => save.mutate()} okButtonProps={{ disabled: !editing?.skill_id, loading: save.isPending }}>
        {editing && (
          <Space orientation="vertical" style={{ width: '100%' }}>
            <Select
              showSearch
              optionFilterProp="label"
              placeholder="Skill"
              style={{ width: '100%' }}
              value={editing.skill_id}
              onChange={(v) => setEditing({ ...editing, skill_id: v })}
              options={(all ?? []).map((s) => ({ value: s.id, label: s.name }))}
            />
            <Space>
              <Rate count={5} value={editing.proficiency} onChange={(v) => setEditing({ ...editing, proficiency: v || 1 })} />
              <Typography.Text>{LEVELS[editing.proficiency]}</Typography.Text>
            </Space>
            <Select style={{ width: '100%' }} value={editing.source} onChange={(v) => setEditing({ ...editing, source: v })} options={SOURCES} />
            <Input.TextArea rows={2} placeholder="Remarks (optional)" value={editing.remarks ?? ''} onChange={(e) => setEditing({ ...editing, remarks: e.target.value })} />
            <Space wrap>
              <Typography.Text type="secondary">Certificate:</Typography.Text>
              {editing.newCert ? (
                <FileAnchor link={editing.newCert} />
              ) : editing.certificate && !editing.removeCert ? (
                <FileAnchor link={editing.certificate} />
              ) : (
                <Typography.Text type="secondary">none</Typography.Text>
              )}
              <UploadButton size="small" category="certificate" onUploaded={(f) => setEditing((e) => e && { ...e, newCert: f, removeCert: false })}>
                {editing.certificate || editing.newCert ? 'Replace' : 'Attach'}
              </UploadButton>
              {(editing.newCert || (editing.certificate && !editing.removeCert)) && (
                <Button size="small" type="link" danger onClick={() => setEditing({ ...editing, newCert: undefined, removeCert: true })}>
                  Remove
                </Button>
              )}
            </Space>
          </Space>
        )}
      </Modal>
    </>
  );
}

function ClassSkills() {
  const { data: classes } = useClasses();
  const [classId, setClassId] = useState<number>();
  const [student, setStudent] = useState<{ id: number; name: string } | null>(null);
  const { data, isFetching } = useQuery({ queryKey: ['skill-matrix', classId], queryFn: () => placementApi.matrix(classId!), enabled: !!classId });

  return (
    <>
      <Select style={{ width: 220, marginBottom: 16 }} placeholder="Pick a class" value={classId} onChange={setClassId} options={(classes ?? []).map((c) => ({ value: c.id, label: c.label }))} />
      {!classId ? (
        <Empty description="Pick a class to see and record its students' skills" />
      ) : (
        <Table
          rowKey="student_id"
          size="small"
          loading={isFetching}
          dataSource={data?.rows}
          pagination={false}
          scroll={{ x: 320 + (data?.skills.length ?? 0) * 110 }}
          onRow={(r) => ({ onClick: () => setStudent({ id: r.student_id, name: r.name }), style: { cursor: 'pointer' } })}
          columns={[
            { title: 'Register no', dataIndex: 'register_no', width: 120, fixed: 'left' },
            { title: 'Name', dataIndex: 'name', width: 170 },
            { title: 'Skills', dataIndex: 'skill_count', width: 70 },
            ...(data?.skills ?? []).map((s) => ({
              title: s.name,
              key: String(s.id),
              width: 110,
              render: (_: unknown, r: { skills: Record<string, number> }) => {
                const l = r.skills[String(s.id)];
                return l ? <Tooltip title={LEVELS[l]}><Tag color={l >= 4 ? 'green' : l >= 3 ? 'blue' : 'default'}>{l}/5</Tag></Tooltip> : <Typography.Text type="secondary">—</Typography.Text>;
              },
            })),
          ]}
        />
      )}
      <Drawer title={student ? `${student.name} · skills` : ''} open={!!student} onClose={() => setStudent(null)} size={Math.min(720, window.innerWidth)} destroyOnHidden>
        {student && <StudentSkillsEditor studentId={student.id} />}
      </Drawer>
    </>
  );
}

function SkillMaster() {
  return (
    <MasterCrud<Skill>
      path="skills"
      perm="skill"
      noun="skill"
      fields={[
        { name: 'name', label: 'Skill name', type: 'text', required: true },
        { name: 'category', label: 'Category', type: 'select', options: CATEGORIES },
      ]}
      columns={[
        { title: 'Skill', dataIndex: 'name' },
        { title: 'Category', dataIndex: 'category', width: 140, render: (v) => <Tag color={CATEGORY_COLORS[v]}>{pretty(v)}</Tag> },
        { title: 'Students', dataIndex: 'student_count', width: 100 },
        { title: 'Job roles', dataIndex: 'job_role_count', width: 100 },
      ]}
    />
  );
}

function OwnOrChildSkills({ parent }: { parent: boolean }) {
  const { data, isLoading } = useQuery({ queryKey: ['students', parent ? 'children' : 'mine'], queryFn: () => studentsApi.list({ page: 1, page_size: parent ? 50 : 1 }) });
  const [selected, setSelected] = useState<number>();
  if (isLoading) return <Spin />;
  const kids = data?.data ?? [];
  if (!kids.length) return <Card><Empty description={parent ? 'No children are linked to your account yet.' : 'Your student profile has not been set up yet.'} /></Card>;
  const active = selected ?? kids[0].id;
  return (
    <Card
      title={parent ? "Children's Skills" : 'My Skills'}
      extra={parent && kids.length > 1 && <Select value={active} onChange={setSelected} style={{ width: 220 }} options={kids.map((k) => ({ value: k.id, label: k.name }))} />}
    >
      <Typography.Paragraph type="secondary">Skills are recorded by your staff after assessments, certifications and projects.</Typography.Paragraph>
      <StudentSkillsEditor studentId={active} />
    </Card>
  );
}

export default function SkillsPage() {
  const { user, can } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  if (audience === 'student') return <OwnOrChildSkills parent={false} />;
  if (audience === 'parent') return <OwnOrChildSkills parent />;
  return (
    <Card>
      <Tabs
        items={[
          { key: 'class', label: 'By class', children: <ClassSkills /> },
          ...(can('skill.view') ? [{ key: 'master', label: 'Skill list', children: <SkillMaster /> }] : []),
          ...(can('subject.view') ? [{ key: 'subjects', label: 'Subject → skills', children: <SubjectSkillMapping /> }] : []),
          ...(can('config.view') ? [{ key: 'scoring', label: 'Scoring weights', children: <ScoringWeights /> }] : []),
        ]}
      />
    </Card>
  );
}
