import { useMemo, useState } from 'react';
import {
  Alert,
  Button,
  Card,
  Checkbox,
  Col,
  Collapse,
  DatePicker,
  Empty,
  Form,
  Input,
  Modal,
  Result,
  Row,
  Select,
  Space,
  Statistic,
  Switch,
  Table,
  Tabs,
  Tag,
  Typography,
  message,
} from 'antd';
import { ArrowRightOutlined, RiseOutlined } from '@ant-design/icons';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import { lifecycleApi, type Preview, type PromotionResult } from '../api/lifecycle';
import { classesApi, mastersApi, studentsApi, type AcademicYear } from '../api/phase2';
import { useAcademicYears } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';

// ---------- semester change ----------

function SemesterChange() {
  const qc = useQueryClient();
  const { data: classes, isLoading } = useQuery({ queryKey: ['classes', 'yearend'], queryFn: () => classesApi.list({}) });
  const [selected, setSelected] = useState<number[]>([]);
  const [result, setResult] = useState<Awaited<ReturnType<typeof lifecycleApi.semesterChange>> | null>(null);

  const change = useMutation({
    mutationFn: (direction: 'next' | 'previous') => lifecycleApi.semesterChange(selected, direction),
    onSuccess: (r) => {
      setResult(r);
      setSelected([]);
      qc.invalidateQueries({ queryKey: ['classes'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const confirm = (direction: 'next' | 'previous') =>
    Modal.confirm({
      title: direction === 'next' ? `Move ${selected.length} class(es) to the next semester?` : `Move ${selected.length} class(es) back a semester?`,
      content: 'Students are enrolled in the new semester; marks entry will default to it.',
      onOk: () => change.mutateAsync(direction),
    });

  return (
    <>
      <Typography.Paragraph type="secondary">
        Use this mid-year, when classes move from the odd to the even semester (e.g. Sem 3 → Sem 4). At the end of the year use <b>Year promotion</b> instead.
      </Typography.Paragraph>
      {result && (
        <Alert
          style={{ marginBottom: 16 }}
          type={result.skipped.length ? 'warning' : 'success'}
          showIcon
          closable
          onClose={() => setResult(null)}
          title={`Moved ${result.changed.length} class(es)${result.skipped.length ? `, skipped ${result.skipped.length}` : ''}`}
          description={
            <>
              {result.changed.map((c) => <div key={c.class_id}>{c.label}: {c.from} → {c.to}</div>)}
              {result.skipped.map((c) => <div key={c.class_id}>{c.label}: {c.reason}</div>)}
            </>
          }
        />
      )}
      <Space style={{ marginBottom: 12 }}>
        <Button type="primary" disabled={!selected.length} loading={change.isPending} onClick={() => confirm('next')}>
          Move to next semester ({selected.length})
        </Button>
        <Button disabled={!selected.length} onClick={() => confirm('previous')}>Move back</Button>
      </Space>
      <Table
        rowKey="id"
        size="small"
        loading={isLoading}
        dataSource={classes}
        pagination={false}
        rowSelection={{ selectedRowKeys: selected, onChange: (k) => setSelected(k as number[]) }}
        columns={[
          { title: 'Class', dataIndex: 'label' },
          { title: 'Current semester', dataIndex: 'current_semester_name', render: (v) => v ?? '—' },
          { title: 'Students', dataIndex: 'student_count', width: 100 },
          { title: 'Incharge', dataIndex: 'class_incharge_name', render: (v) => v ?? '—' },
        ]}
      />
    </>
  );
}

// ---------- year promotion ----------

function NewYearModal({ open, onClose, after }: { open: boolean; onClose: () => void; after?: AcademicYear }) {
  const qc = useQueryClient();
  const [form] = Form.useForm();
  const create = useMutation({
    mutationFn: (v: { name: string; start_date: dayjs.Dayjs; end_date: dayjs.Dayjs }) =>
      mastersApi.create('academic-years', { name: v.name, start_date: v.start_date.format('YYYY-MM-DD'), end_date: v.end_date.format('YYYY-MM-DD'), is_current: false }),
    onSuccess: () => {
      message.success('Academic year created');
      qc.invalidateQueries({ queryKey: ['lookup', 'academic-years'] });
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const start = after ? dayjs(after.end_date).add(1, 'day') : dayjs().startOf('year').add(5, 'month');
  return (
    <Modal title="New academic year" open={open} onCancel={onClose} onOk={() => form.submit()} okButtonProps={{ loading: create.isPending }} destroyOnHidden>
      <Form form={form} layout="vertical" preserve={false} onFinish={(v) => create.mutate(v)}
        initialValues={{ name: `${start.year()}-${String((start.year() + 1) % 100).padStart(2, '0')}`, start_date: start, end_date: start.add(1, 'year').subtract(1, 'day') }}>
        <Form.Item name="name" label="Name" rules={[{ required: true }]}><Input /></Form.Item>
        <Row gutter={12}>
          <Col span={12}><Form.Item name="start_date" label="Starts" rules={[{ required: true }]}><DatePicker format="DD-MM-YYYY" style={{ width: '100%' }} /></Form.Item></Col>
          <Col span={12}><Form.Item name="end_date" label="Ends" rules={[{ required: true }]}><DatePicker format="DD-MM-YYYY" style={{ width: '100%' }} /></Form.Item></Col>
        </Row>
      </Form>
    </Modal>
  );
}

function Promotion() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data: years } = useAcademicYears();
  const current = years?.find((y) => y.is_current);
  const [fromId, setFromId] = useState<number>();
  const [toId, setToId] = useState<number>();
  const [detained, setDetained] = useState<Set<number>>(new Set());
  const [carry, setCarry] = useState(true);
  const [setCurrent, setSetCurrent] = useState(true);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [result, setResult] = useState<PromotionResult | null>(null);
  const [newYear, setNewYear] = useState(false);
  const from = fromId ?? current?.id;
  const fromYear = years?.find((y) => y.id === from);
  const later = (years ?? []).filter((y) => fromYear && dayjs(y.start_date).isAfter(dayjs(fromYear.start_date)));
  const runs = useQuery({ queryKey: ['promotion-runs'], queryFn: lifecycleApi.runs });

  const load = useMutation({
    mutationFn: () => lifecycleApi.preview(from!, toId!),
    onSuccess: (p) => {
      setPreview(p);
      setResult(null);
      setDetained(new Set());
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const run = useMutation({
    mutationFn: () => lifecycleApi.promote({ from_year_id: from!, to_year_id: toId!, detained_student_ids: [...detained], carry_incharge: carry, set_current: setCurrent }),
    onSuccess: (r) => {
      setResult(r);
      setPreview(null);
      qc.invalidateQueries();
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  const counts = useMemo(() => {
    if (!preview) return { promote: 0, detain: 0, passOut: 0 };
    let promote = 0, passOut = 0;
    preview.classes.forEach((c) => c.students.forEach((s) => {
      if (detained.has(s.id)) return;
      if (c.action === 'pass_out') passOut++;
      else promote++;
    }));
    return { promote, detain: detained.size, passOut };
  }, [preview, detained]);

  const toggle = (id: number) => setDetained((d) => {
    const n = new Set(d);
    if (n.has(id)) n.delete(id);
    else n.add(id);
    return n;
  });

  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      <Typography.Paragraph type="secondary" style={{ margin: 0 }}>
        At the end of an academic year, move every student up one year: next year's classes are created (CSE II-A → CSE III-A),
        final-year students become alumni, and students you mark as detained repeat their year. Everything happens in one step and is recorded below.
      </Typography.Paragraph>
      {can('promotion.create') ? (
        <Card size="small">
          <Space wrap align="end">
            <div>
              <Typography.Text type="secondary">From</Typography.Text><br />
              <Select style={{ width: 180 }} value={from} onChange={(v) => { setFromId(v); setToId(undefined); setPreview(null); }}
                options={(years ?? []).map((y) => ({ value: y.id, label: y.is_current ? `${y.name} (current)` : y.name }))} />
            </div>
            <ArrowRightOutlined style={{ marginBottom: 8 }} />
            <div>
              <Typography.Text type="secondary">To</Typography.Text><br />
              <Select style={{ width: 180 }} placeholder="Next year" value={toId} onChange={(v) => { setToId(v); setPreview(null); }}
                options={later.map((y) => ({ value: y.id, label: y.name }))} notFoundContent="Create the next academic year first" />
            </div>
            <Button onClick={() => setNewYear(true)}>+ New academic year</Button>
            <Button type="primary" disabled={!from || !toId} loading={load.isPending} onClick={() => load.mutate()}>Preview</Button>
          </Space>
        </Card>
      ) : (
        <Alert type="info" showIcon title="Year promotion is run by an administrator. You can see the history below." />
      )}

      {result && (
        <Result
          status="success"
          title="Promotion complete"
          subTitle={`${result.promoted} promoted · ${result.detained} detained · ${result.passed_out} passed out · ${result.classes_created} classes created`}
          extra={<Table size="small" rowKey="class" pagination={false} dataSource={result.classes}
            columns={[{ title: 'Class', dataIndex: 'class' }, { title: 'Promoted', dataIndex: 'promoted' }, { title: 'Detained', dataIndex: 'detained' }, { title: 'Passed out', dataIndex: 'passed_out' }]} />}
        />
      )}

      {preview && (
        <Card title={`Preview: ${preview.from.name} → ${preview.to.name}`}>
          {preview.already_run && <Alert type="warning" showIcon style={{ marginBottom: 16 }} title={`Students were already promoted from ${preview.from.name} to ${preview.to.name}.`} />}
          <Row gutter={16} style={{ marginBottom: 16 }}>
            <Col xs={8}><Statistic title="Promote" value={counts.promote} styles={{ content: { color: '#16a34a' } }} /></Col>
            <Col xs={8}><Statistic title="Detain" value={counts.detain} styles={{ content: { color: counts.detain ? '#d97706' : undefined } }} /></Col>
            <Col xs={8}><Statistic title="Pass out (alumni)" value={counts.passOut} styles={{ content: { color: '#7c3aed' } }} /></Col>
          </Row>
          <Typography.Paragraph type="secondary">Tick students who must repeat the year. Students with backlogs are highlighted but are promoted unless you detain them.</Typography.Paragraph>
          <Collapse
            items={preview.classes.map((c) => ({
              key: c.class_id,
              label: (
                <Space wrap>
                  <b>{c.label}</b>
                  <ArrowRightOutlined />
                  {c.action === 'pass_out' ? <Tag color="purple">Passed out</Tag> : <Tag color="green">{c.target_label}{c.target_exists ? '' : ' (new)'}</Tag>}
                  <Typography.Text type="secondary">{c.students.length} students{c.incharge_name ? ` · incharge ${c.incharge_name}` : ''}</Typography.Text>
                  {c.students.some((s) => detained.has(s.id)) && <Tag color="orange">{c.students.filter((s) => detained.has(s.id)).length} detained</Tag>}
                </Space>
              ),
              children: c.students.length ? (
                <Table size="small" rowKey="id" pagination={false} dataSource={c.students}
                  columns={[
                    { title: 'Detain', width: 80, render: (_, s) => <Checkbox checked={detained.has(s.id)} onChange={() => toggle(s.id)} /> },
                    { title: 'Register no', dataIndex: 'register_no', width: 130 },
                    { title: 'Name', dataIndex: 'name' },
                    { title: 'CGPA', dataIndex: 'cgpa', width: 80 },
                    { title: 'Backlogs', dataIndex: 'backlog_count', width: 100, render: (v) => (v ? <Tag color="red">{v}</Tag> : 0) },
                  ]} />
              ) : <Empty description="No students" />,
            }))}
          />
          <Space wrap style={{ marginTop: 16 }}>
            <Space><Switch checked={carry} onChange={setCarry} /> Carry class incharges to the next year</Space>
            <Space><Switch checked={setCurrent} onChange={setSetCurrent} /> Make {preview.to.name} the current academic year</Space>
          </Space>
          <div style={{ marginTop: 16 }}>
            <Button type="primary" danger icon={<RiseOutlined />} disabled={preview.already_run} loading={run.isPending}
              onClick={() => Modal.confirm({
                title: `Promote students from ${preview.from.name} to ${preview.to.name}?`,
                content: `${counts.promote} promoted, ${counts.detain} detained, ${counts.passOut} passed out. This cannot be undone.`,
                okText: 'Promote',
                okButtonProps: { danger: true },
                onOk: () => run.mutateAsync(),
              })}>
              Run promotion
            </Button>
          </div>
        </Card>
      )}

      <Card size="small" title="Promotion history">
        <Table size="small" rowKey="id" loading={runs.isLoading} dataSource={runs.data} pagination={false} locale={{ emptyText: 'No promotions yet' }}
          columns={[
            { title: 'When', dataIndex: 'created_at', render: (v) => dayjs(v).format('DD MMM YYYY, HH:mm') },
            { title: 'Years', render: (_, r) => `${r.from_year} → ${r.to_year}` },
            { title: 'Promoted', dataIndex: 'promoted_count' },
            { title: 'Detained', dataIndex: 'detained_count' },
            { title: 'Passed out', dataIndex: 'passed_out_count' },
            { title: 'Classes created', dataIndex: 'classes_created' },
            { title: 'By', dataIndex: 'created_by_name' },
          ]} />
      </Card>
      <NewYearModal open={newYear} onClose={() => setNewYear(false)} after={later[later.length - 1] ?? fromYear} />
    </Space>
  );
}

// ---------- alumni ----------

function Alumni() {
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const { data, isFetching } = useQuery({
    queryKey: ['students', 'alumni', search, page],
    queryFn: () => studentsApi.list({ page, page_size: 25, search, lifecycle: 'passed_out' }),
    placeholderData: keepPreviousData,
  });
  return (
    <>
      <Input.Search allowClear placeholder="Name or register number" style={{ width: 280, marginBottom: 16 }} onSearch={(v) => { setSearch(v); setPage(1); }} />
      <Table rowKey="id" size="small" loading={isFetching} dataSource={data?.data} scroll={{ x: 760 }}
        pagination={{ current: page, pageSize: 25, total: data?.meta.total, onChange: setPage, hideOnSinglePage: true }}
        locale={{ emptyText: 'No alumni yet. Final-year students become alumni when the year is promoted.' }}
        columns={[
          { title: 'Register no', dataIndex: 'register_no', width: 130 },
          { title: 'Name', dataIndex: 'name' },
          { title: 'Department', dataIndex: 'department_code', width: 110 },
          { title: 'Batch', dataIndex: 'batch', width: 110 },
          { title: 'Passed out', dataIndex: 'passed_out_year', width: 110 },
          { title: 'CGPA', dataIndex: 'cgpa', width: 80 },
          { title: 'Backlogs', dataIndex: 'backlog_count', width: 100, render: (v) => (v ? <Tag color="red">{v}</Tag> : 0) },
        ]} />
    </>
  );
}

export default function YearEndPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs items={[
        ...(can('promotion.create', 'class.update') ? [{ key: 'sem', label: 'Semester change', children: <SemesterChange /> }] : []),
        { key: 'promo', label: 'Year promotion', children: <Promotion /> },
        { key: 'alumni', label: 'Alumni', children: <Alumni /> },
      ]} />
    </Card>
  );
}
