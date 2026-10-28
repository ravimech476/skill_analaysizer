import { useState } from 'react';
import dayjs from 'dayjs';
import { Alert, Button, Card, Empty, Form, Input, Modal, Popconfirm, Select, Space, Table, Tag, Typography, Upload, message } from 'antd';
import type { UploadFile } from 'antd';
import { DeleteOutlined, InboxOutlined, SearchOutlined, UploadOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { KB_DOC_TYPES, kbApi, type KbDocument, type KbHit } from '../api/kb';
import { useDepartments, useSubjects } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';

const TYPE_COLORS: Record<string, string> = {
  syllabus: 'blue',
  notes: 'green',
  question_paper: 'orange',
  placement: 'purple',
  resume: 'cyan',
  roadmap: 'magenta',
  other: 'default',
};
const typeLabel = (v: string) => KB_DOC_TYPES.find((t) => t.value === v)?.label ?? v;

interface UploadForm {
  title?: string;
  doc_type: string;
  department_id?: number;
  subject_id?: number;
}

/** Staff page: documents the AI assistant can search (syllabus, notes, question papers…). */
export default function KnowledgeBasePage() {
  const qc = useQueryClient();
  const { hasRole } = useAuth();
  const crossDepartment = hasRole('admin', 'placement_officer');
  const { data: docs, isLoading } = useQuery({ queryKey: ['kb', 'documents'], queryFn: kbApi.list });
  const { data: departments } = useDepartments();
  const { data: subjects } = useSubjects();

  const [open, setOpen] = useState(false);
  const [files, setFiles] = useState<UploadFile[]>([]);
  const [form] = Form.useForm<UploadForm>();

  const upload = useMutation({
    mutationFn: (v: UploadForm) => kbApi.upload({ ...v, file: files[0].originFileObj as File }),
    onSuccess: (r) => {
      message.success(`Indexed "${r.title}" as ${r.chunk_count} passage${r.chunk_count === 1 ? '' : 's'}`);
      qc.invalidateQueries({ queryKey: ['kb', 'documents'] });
      setOpen(false);
      setFiles([]);
      form.resetFields();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const remove = useMutation({
    mutationFn: kbApi.remove,
    onSuccess: () => {
      message.success('Removed');
      qc.invalidateQueries({ queryKey: ['kb', 'documents'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  const [query, setQuery] = useState('');
  const [hits, setHits] = useState<KbHit[] | null>(null);
  const search = useMutation({
    mutationFn: kbApi.search,
    onSuccess: setHits,
    onError: (e) => message.error(errorMessage(e)),
  });
  const runSearch = () => {
    if (query.trim()) search.mutate(query.trim());
  };

  return (
    <Space orientation="vertical" size={16} style={{ width: '100%' }}>
      <Card
        title="Knowledge base"
        extra={
          <Button type="primary" icon={<UploadOutlined />} onClick={() => setOpen(true)}>
            Upload document
          </Button>
        }
      >
        <Typography.Paragraph type="secondary" style={{ marginBottom: 16 }}>
          Documents added here are cut into passages and indexed, so the AI assistant can answer questions from them and show which document it used.
          Supported: PDF, Word (.docx), text and Markdown, up to 10 MB. Scanned PDFs are not supported.
        </Typography.Paragraph>
        <Table<KbDocument>
          rowKey="id"
          size="middle"
          loading={isLoading}
          dataSource={docs ?? []}
          pagination={{ pageSize: 10, hideOnSinglePage: true }}
          scroll={{ x: 760 }}
          locale={{ emptyText: <Empty description="No documents yet. Upload a syllabus or notes to get started." /> }}
          columns={[
            { title: 'Title', dataIndex: 'title', width: 260, render: (v, r) => (<><div style={{ fontWeight: 500 }}>{v}</div><Typography.Text type="secondary" style={{ fontSize: 12 }}>{r.source_name}</Typography.Text></>) },
            { title: 'Type', dataIndex: 'doc_type', width: 130, render: (v: string) => <Tag color={TYPE_COLORS[v]}>{typeLabel(v)}</Tag> },
            { title: 'Department', dataIndex: 'department_name', width: 150, render: (v) => v ?? <Typography.Text type="secondary">Everyone</Typography.Text> },
            { title: 'Subject', dataIndex: 'subject_name', width: 170, render: (v) => v ?? '—' },
            { title: 'Passages', dataIndex: 'chunk_count', width: 90, align: 'right' },
            { title: 'Uploaded', dataIndex: 'created_at', width: 130, render: (v: string) => dayjs(v).format('DD MMM, HH:mm') },
            {
              title: '',
              width: 56,
              render: (_, r) => (
                <Popconfirm title="Remove this document?" description="The assistant will stop using it." okText="Remove" okButtonProps={{ danger: true }} onConfirm={() => remove.mutate(r.id)}>
                  <Button type="text" danger icon={<DeleteOutlined />} aria-label={`Remove ${r.title}`} />
                </Popconfirm>
              ),
            },
          ]}
        />
      </Card>

      <Card title="Test search">
        <Typography.Paragraph type="secondary">Ask a question the way a student would, and see which passages the assistant would find.</Typography.Paragraph>
        <Space.Compact style={{ width: '100%', maxWidth: 640 }}>
          <Input value={query} onChange={(e) => setQuery(e.target.value)} onPressEnter={runSearch} placeholder="e.g. Which topics are in the graphs unit?" maxLength={500} />
          <Button type="primary" icon={<SearchOutlined />} loading={search.isPending} onClick={runSearch}>
            Search
          </Button>
        </Space.Compact>
        {hits && (
          <div style={{ marginTop: 16 }}>
            {hits.length === 0 ? (
              <Alert type="info" showIcon title="No passage matched closely enough. The assistant would answer without document sources." />
            ) : (
              <Space orientation="vertical" size={10} style={{ width: '100%' }}>
                {hits.map((h, i) => (
                  <Card key={`${h.document_id}-${i}`} size="small" title={<Space><Tag color={TYPE_COLORS[h.doc_type]}>{typeLabel(h.doc_type)}</Tag>{h.title}</Space>} extra={<Tag color="success">{Math.round(h.score * 100)}% match</Tag>}>
                    <Typography.Paragraph type="secondary" style={{ margin: 0 }} ellipsis={{ rows: 4, expandable: 'collapsible' }}>{h.content}</Typography.Paragraph>
                  </Card>
                ))}
              </Space>
            )}
          </div>
        )}
      </Card>

      <Modal
        title="Upload document"
        open={open}
        okText="Upload and index"
        onCancel={() => !upload.isPending && setOpen(false)}
        okButtonProps={{ disabled: files.length === 0, loading: upload.isPending }}
        cancelButtonProps={{ disabled: upload.isPending }}
        onOk={() => form.validateFields().then((v) => upload.mutate(v))}
        destroyOnHidden
      >
        <Form form={form} layout="vertical" initialValues={{ doc_type: 'notes' }} disabled={upload.isPending}>
          <Form.Item label="File" required>
            <Upload.Dragger
              accept=".pdf,.docx,.txt,.md"
              maxCount={1}
              fileList={files}
              beforeUpload={(f) => {
                if (f.size > 10 * 1024 * 1024) {
                  message.error('File is larger than 10 MB');
                  return Upload.LIST_IGNORE;
                }
                return false; // keep it local; we send it with the form
              }}
              onChange={(e) => setFiles(e.fileList.slice(-1))}
            >
              <p className="ant-upload-drag-icon"><InboxOutlined /></p>
              <p className="ant-upload-text">Click or drag a file here</p>
              <p className="ant-upload-hint">PDF, DOCX, TXT or MD, up to 10 MB</p>
            </Upload.Dragger>
          </Form.Item>
          <Form.Item name="title" label="Title" extra="Shown to students under answers. Defaults to the file name.">
            <Input maxLength={200} />
          </Form.Item>
          <Form.Item name="doc_type" label="Type" rules={[{ required: true }]}>
            <Select options={KB_DOC_TYPES} />
          </Form.Item>
          {crossDepartment ? (
            <Form.Item name="department_id" label="Department" extra="Leave empty to share with every department.">
              <Select allowClear placeholder="Everyone" options={(departments ?? []).map((d) => ({ value: d.id, label: d.name }))} showSearch optionFilterProp="label" />
            </Form.Item>
          ) : (
            <Typography.Paragraph type="secondary">This document will be shared with your own department.</Typography.Paragraph>
          )}
          <Form.Item name="subject_id" label="Subject (optional)">
            <Select allowClear placeholder="None" options={(subjects ?? []).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }))} showSearch optionFilterProp="label" />
          </Form.Item>
        </Form>
        {upload.isPending && <Alert type="info" showIcon title="Indexing… a long document can take a minute or two." />}
      </Modal>
    </Space>
  );
}
