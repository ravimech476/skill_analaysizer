import { useState, type ReactNode } from 'react';
import { Alert, Button, Card, Checkbox, Col, Input, Result, Row, Select, Space, Statistic, Table, Tabs, Tag, Typography, Upload, message } from 'antd';
import { DownloadOutlined, InboxOutlined } from '@ant-design/icons';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import { bulkApi, saveBlob, type UploadJob } from '../api/phase2';
import { uploadsApi } from '../api/reports';
import { useClasses } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';

const TYPE_LABEL: Record<string, string> = { students: 'Students', staff: 'Staff', skills: 'Skills', marks: 'Marks' };

export function JobResult({ job, codeLabel = 'Register no', okLabel = 'Created' }: { job: UploadJob; codeLabel?: string; okLabel?: string }) {
  const allOk = job.failed_rows === 0;
  return (
    <Card
      title={
        <Space>
          Result: {job.file_name}
          {job.dry_run && <Tag color="blue">Dry run: nothing was saved</Tag>}
        </Space>
      }
      extra={
        job.failed_rows > 0 && (
          <Button icon={<DownloadOutlined />} onClick={() => bulkApi.errorReport(job.id).then((b) => saveBlob(b, `upload_${job.id}_errors.xlsx`))}>
            Download error report
          </Button>
        )
      }
    >
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col xs={8}>
          <Statistic title="Rows" value={job.total_rows} />
        </Col>
        <Col xs={8}>
          <Statistic title={job.dry_run ? `Would be ${okLabel.toLowerCase()}` : okLabel} value={job.success_rows} styles={{ content: { color: '#16a34a' } }} />
        </Col>
        <Col xs={8}>
          <Statistic title="Failed" value={job.failed_rows} styles={{ content: { color: job.failed_rows ? '#dc2626' : undefined } }} />
        </Col>
      </Row>
      {allOk ? (
        <Alert type="success" showIcon title={job.dry_run ? 'Every row is valid. Untick "Dry run" and upload again to save.' : 'All rows imported.'} />
      ) : (
        <Table
          rowKey={(e) => `${e.row}-${e.register_no}-${e.message}`}
          size="small"
          dataSource={job.errors ?? []}
          pagination={{ pageSize: 10, hideOnSinglePage: true }}
          scroll={{ x: 560 }}
          columns={[
            { title: 'Row', dataIndex: 'row', width: 70, render: (v) => v || '—' },
            { title: codeLabel, dataIndex: 'register_no', width: 130 },
            { title: 'Name', dataIndex: 'name', width: 180 },
            { title: 'Problem', dataIndex: 'message', render: (v) => <Typography.Text type="danger">{v}</Typography.Text> },
          ]}
        />
      )}
    </Card>
  );
}

/** Drop zone that holds one .xlsx until the user presses the action button. */
export function XlsxPicker({ file, onChange }: { file: File | null; onChange: (f: File | null) => void }) {
  return (
    <Upload.Dragger
      accept=".xlsx"
      maxCount={1}
      beforeUpload={(f) => {
        onChange(f);
        return false; // uploaded on button click
      }}
      onRemove={() => onChange(null)}
      fileList={file ? [{ uid: '1', name: file.name, status: 'done' }] : []}
    >
      <p className="ant-upload-drag-icon">
        <InboxOutlined />
      </p>
      <p className="ant-upload-text">Click or drag the Excel file here</p>
      <p className="ant-upload-hint">.xlsx, up to 5 MB / 5,000 rows</p>
    </Upload.Dragger>
  );
}

interface PanelProps {
  title: string;
  help: ReactNode;
  template: ReactNode;
  options?: ReactNode;
  actionLabel: string;
  codeLabel: string;
  okLabel: string;
  canSubmit?: boolean;
  run: (file: File, dryRun: boolean) => Promise<UploadJob>;
  onSaved?: () => void;
}

function UploadPanel({ title, help, template, options, actionLabel, codeLabel, okLabel, canSubmit = true, run, onSaved }: PanelProps) {
  const qc = useQueryClient();
  const [file, setFile] = useState<File | null>(null);
  const [dryRun, setDryRun] = useState(true);
  const [result, setResult] = useState<UploadJob | null>(null);
  const upload = useMutation({
    mutationFn: () => run(file!, dryRun),
    onSuccess: (job) => {
      setResult(job);
      qc.invalidateQueries({ queryKey: ['bulk-jobs'] });
      if (!job.dry_run && job.success_rows) onSaved?.();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      <Row gutter={[24, 24]}>
        <Col xs={24} lg={10}>
          <Typography.Title level={5} style={{ marginTop: 0 }}>1. Download the template</Typography.Title>
          <Typography.Paragraph type="secondary">{help}</Typography.Paragraph>
          {template}
        </Col>
        <Col xs={24} lg={14}>
          <Typography.Title level={5} style={{ marginTop: 0 }}>2. Upload the filled sheet</Typography.Title>
          <XlsxPicker
            file={file}
            onChange={(f) => {
              setFile(f);
              setResult(null);
            }}
          />
          <Space orientation="vertical" style={{ marginTop: 16, width: '100%' }}>
            <Checkbox checked={dryRun} onChange={(e) => setDryRun(e.target.checked)}>
              <b>Dry run</b>: check every row without saving anything
            </Checkbox>
            {options}
            <Button type="primary" disabled={!file || !canSubmit} loading={upload.isPending} onClick={() => upload.mutate()}>
              {dryRun ? 'Validate file' : actionLabel}
            </Button>
          </Space>
        </Col>
      </Row>
      {upload.isPending && <Result icon={<InboxOutlined />} title="Processing…" subTitle={`${title}: large files can take a minute.`} />}
      {result && <JobResult job={result} codeLabel={codeLabel} okLabel={okLabel} />}
    </Space>
  );
}

function PasswordOption({ value, onChange, who }: { value: string; onChange: (v: string) => void; who: string }) {
  return (
    <>
      <Input.Password
        placeholder={`Default password for new ${who} (optional, min 8 chars)`}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        autoComplete="new-password"
        style={{ maxWidth: 420 }}
      />
      <Typography.Text type="secondary">Without a default password, they sign in with OTP.</Typography.Text>
    </>
  );
}

function StudentsUpload() {
  const qc = useQueryClient();
  const [createClasses, setCreateClasses] = useState(false);
  const [password, setPassword] = useState('');
  return (
    <UploadPanel
      title="Students"
      codeLabel="Register no"
      okLabel="Created"
      actionLabel="Import students"
      canSubmit={!password || password.length >= 8}
      help="One row per student. Columns marked * are required. The Instructions sheet explains each column and the Departments sheet lists the codes. Each row can include one parent; parents with the same mobile number share one account, so siblings are linked."
      template={
        <Button icon={<DownloadOutlined />} onClick={() => bulkApi.template().then((b) => saveBlob(b, 'student_upload_template.xlsx')).catch((e) => message.error(errorMessage(e)))}>
          Download template (.xlsx)
        </Button>
      }
      options={
        <>
          <Checkbox checked={createClasses} onChange={(e) => setCreateClasses(e.target.checked)}>
            Create missing classes in the current academic year
          </Checkbox>
          <PasswordOption value={password} onChange={setPassword} who="students" />
        </>
      }
      run={(file, dry_run) => bulkApi.upload(file, { dry_run, create_missing_classes: createClasses, default_password: password || undefined })}
      onSaved={() => {
        qc.invalidateQueries({ queryKey: ['students'] });
        qc.invalidateQueries({ queryKey: ['classes'] });
      }}
    />
  );
}

function StaffUpload() {
  const qc = useQueryClient();
  const [password, setPassword] = useState('');
  return (
    <UploadPanel
      title="Staff"
      codeLabel="Employee code"
      okLabel="Created"
      actionLabel="Import staff"
      canSubmit={!password || password.length >= 8}
      help="One row per staff member. The employee code becomes the login username. Roles can be staff, hod and placement_officer, separated by commas; staff is the default."
      template={
        <Button icon={<DownloadOutlined />} onClick={() => uploadsApi.staffTemplate()}>
          Download template (.xlsx)
        </Button>
      }
      options={<PasswordOption value={password} onChange={setPassword} who="staff" />}
      run={(file, dry_run) => uploadsApi.staff(file, { dry_run, default_password: password || undefined })}
      onSaved={() => qc.invalidateQueries({ queryKey: ['staff'] })}
    />
  );
}

function SkillsUpload() {
  const qc = useQueryClient();
  const { data: classes } = useClasses();
  const [classId, setClassId] = useState<number>();
  return (
    <UploadPanel
      title="Skills"
      codeLabel="Register no"
      okLabel="Saved"
      actionLabel="Save skill levels"
      help="One row per student and skill, level 1 (Beginner) to 5 (Expert). Existing levels are updated. Rows with a blank level are skipped. Pick a class to get the template pre-filled with its students; staff can only record skills for their own department."
      template={
        <Space wrap>
          <Select
            allowClear
            style={{ width: 200 }}
            placeholder="Blank template"
            value={classId}
            onChange={setClassId}
            options={(classes ?? []).map((c) => ({ value: c.id, label: c.label }))}
          />
          <Button icon={<DownloadOutlined />} onClick={() => uploadsApi.skillsTemplate(classId ? { class_id: classId } : undefined)}>
            Download template (.xlsx)
          </Button>
        </Space>
      }
      run={(file, dry_run) => uploadsApi.skills(file, { dry_run })}
      onSaved={() => qc.invalidateQueries({ queryKey: ['student-skills'] })}
    />
  );
}

function History() {
  const [page, setPage] = useState(1);
  const [type, setType] = useState<string>();
  const [open, setOpen] = useState<UploadJob | null>(null);
  const { data: jobs, isFetching } = useQuery({
    queryKey: ['bulk-jobs', page, type],
    queryFn: () => bulkApi.jobs(page, 10, type),
    placeholderData: keepPreviousData,
  });
  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      {open && <JobResult job={open} codeLabel={open.upload_type === 'staff' ? 'Employee code' : 'Register no'} okLabel={open.upload_type === 'students' || open.upload_type === 'staff' ? 'Created' : 'Saved'} />}
      <Card
        title="Upload history"
        extra={
          <Select
            allowClear
            size="small"
            style={{ width: 150 }}
            placeholder="All uploads"
            value={type}
            onChange={(v) => {
              setType(v);
              setPage(1);
            }}
            options={Object.entries(TYPE_LABEL).map(([value, label]) => ({ value, label }))}
          />
        }
      >
        <Table<UploadJob>
          rowKey="id"
          size="small"
          loading={isFetching}
          dataSource={jobs?.data}
          scroll={{ x: 760 }}
          pagination={{ current: page, pageSize: 10, total: jobs?.meta.total, onChange: setPage, hideOnSinglePage: true }}
          onRow={(j) => ({
            onClick: () =>
              bulkApi
                .job(j.id)
                .then((full) => {
                  setOpen(full);
                  window.scrollTo({ top: 0, behavior: 'smooth' });
                })
                .catch((e) => message.error(errorMessage(e))),
            style: { cursor: 'pointer' },
          })}
          columns={[
            { title: 'When', dataIndex: 'created_at', render: (v) => dayjs(v).format('DD MMM YYYY, HH:mm') },
            { title: 'Type', dataIndex: 'upload_type', width: 90, render: (v) => <Tag>{TYPE_LABEL[v] ?? v}</Tag> },
            { title: 'File', dataIndex: 'file_name', render: (v, j) => <Space>{v}{j.dry_run && <Tag color="blue">dry run</Tag>}</Space> },
            { title: 'By', dataIndex: 'created_by_name' },
            { title: 'Rows', dataIndex: 'total_rows', width: 70 },
            { title: 'OK', dataIndex: 'success_rows', width: 70, render: (v) => <Typography.Text type="success">{v}</Typography.Text> },
            { title: 'Failed', dataIndex: 'failed_rows', width: 80, render: (v) => (v ? <Typography.Text type="danger">{v}</Typography.Text> : 0) },
          ]}
        />
      </Card>
    </Space>
  );
}

export default function BulkUploadPage() {
  const { can } = useAuth();
  const tabs = [
    ...(can('bulk_upload.create') ? [{ key: 'students', label: 'Students', children: <StudentsUpload /> }] : []),
    ...(can('staff.create') ? [{ key: 'staff', label: 'Staff', children: <StaffUpload /> }] : []),
    ...(can('student_skill.create') ? [{ key: 'skills', label: 'Student skills', children: <SkillsUpload /> }] : []),
    ...(can('bulk_upload.view') ? [{ key: 'history', label: 'History', children: <History /> }] : []),
  ];
  return (
    <Card>
      <Typography.Paragraph type="secondary">
        Marks are uploaded from <b>Marks → Enter marks</b>, one class, subject and exam at a time.
      </Typography.Paragraph>
      <Tabs items={tabs} destroyOnHidden />
    </Card>
  );
}
