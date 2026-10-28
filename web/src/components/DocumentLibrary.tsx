import { useState, type ReactNode } from 'react';
import { Alert, Button, Checkbox, Form, List, Modal, Space, Tag, Typography, Upload, message, type FormInstance, type UploadFile } from 'antd';
import { CheckCircleFilled, CloseCircleFilled, InboxOutlined, LoadingOutlined, RobotOutlined, UploadOutlined } from '@ant-design/icons';
import { errorMessage } from '../api/client';
import { FILE_RULES, filesApi, type FileCategory, type FileLink } from '../api/files';
import { kbApi } from '../api/kb';
import { mastersApi, type MasterPath } from '../api/phase2';
import { FileSlot } from './Files';

export type DocPath = 'study-materials' | 'interview-documents' | 'question-papers';

const readableByAI = (name: string) => /\.(pdf|docx)$/i.test(name);

/** Adds a row's attached file to the AI assistant's knowledge base (PDF and Word only). */
export function IndexForAI({ path, id, file }: { path: DocPath; id: number; file: FileLink }) {
  const [busy, setBusy] = useState(false);
  const ok = readableByAI(file.name);
  return (
    <Button
      size="small"
      icon={<RobotOutlined />}
      loading={busy}
      disabled={!ok}
      title={ok ? 'Let the AI assistant answer questions from this file' : 'The AI assistant can read PDF and Word files only'}
      onClick={() => {
        setBusy(true);
        kbApi
          .indexDocument(path, id)
          .then((r) => message.success(`Added to the AI knowledge base (${r.chunk_count} passage${r.chunk_count === 1 ? '' : 's'})`))
          .catch((e) => message.error(errorMessage(e)))
          .finally(() => setBusy(false));
      }}
    >
      Add to AI
    </Button>
  );
}

/** The File column of a document table: open, replace or remove the file, and add it to the AI. */
export function DocumentFileCell({
  path,
  category,
  id,
  file,
  canEdit,
  canIndex,
  onChanged,
}: {
  path: DocPath;
  category: FileCategory;
  id: number;
  file: FileLink | null;
  canEdit: boolean;
  canIndex: boolean;
  onChanged: () => void;
}) {
  return (
    <Space orientation="vertical" size={4}>
      <FileSlot
        category={category}
        value={file}
        canEdit={canEdit}
        emptyText="No file"
        save={(fileId) => filesApi.setDocumentFile(path, id, fileId).then(onChanged)}
      />
      {canIndex && file && <IndexForAI path={path} id={id} file={file} />}
    </Space>
  );
}

type Status = { state: 'waiting' | 'working' | 'done' | 'failed'; note?: string };

/**
 * Upload many documents at once. Each file becomes one row (titled after the file name) using the shared
 * details from the form; the file is stored, attached, and optionally added to the AI knowledge base.
 */
export function MultiUpload({
  label,
  path,
  category,
  masterPath,
  initialValues,
  children,
  onDone,
}: {
  label: string;
  path: DocPath;
  category: FileCategory;
  masterPath: MasterPath;
  initialValues?: Record<string, unknown>;
  /** Form items for the details shared by every file (company, subject, year…). */
  children: (form: FormInstance) => ReactNode;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [files, setFiles] = useState<UploadFile[]>([]);
  const [addToAI, setAddToAI] = useState(true);
  const [running, setRunning] = useState(false);
  const [status, setStatus] = useState<Record<string, Status>>({});
  const [form] = Form.useForm();
  const rule = FILE_RULES[category];

  const set = (uid: string, s: Status) => setStatus((cur) => ({ ...cur, [uid]: s }));

  const run = async () => {
    const shared = await form.validateFields();
    setRunning(true);
    let ok = 0;
    for (const f of files) {
      const raw = f.originFileObj as File;
      set(f.uid, { state: 'working' });
      try {
        const stored = await filesApi.upload(category, raw);
        const row = await mastersApi.create<{ id: number }>(masterPath, { ...shared, title: raw.name.replace(/\.[^.]+$/, '').slice(0, 200) });
        await filesApi.setDocumentFile(path, row.id, stored.id);
        let note: string | undefined;
        if (addToAI) {
          if (readableByAI(raw.name)) {
            await kbApi.indexDocument(path, row.id).catch((e) => {
              note = `Saved, but not added to the AI: ${errorMessage(e)}`;
            });
          } else {
            note = 'Saved. PowerPoint files cannot be added to the AI yet.';
          }
        }
        set(f.uid, { state: 'done', note });
        ok++;
      } catch (e) {
        set(f.uid, { state: 'failed', note: errorMessage(e) });
      }
    }
    setRunning(false);
    if (ok > 0) {
      message.success(`${ok} document${ok === 1 ? '' : 's'} uploaded`);
      onDone();
    }
  };

  const finished = files.length > 0 && files.every((f) => status[f.uid]?.state === 'done' || status[f.uid]?.state === 'failed');
  const close = () => {
    if (running) return;
    setOpen(false);
    setFiles([]);
    setStatus({});
    form.resetFields();
  };

  return (
    <>
      <Button icon={<UploadOutlined />} onClick={() => setOpen(true)}>
        Upload documents
      </Button>
      <Modal
        title={label}
        open={open}
        width={640}
        onCancel={close}
        destroyOnHidden
        footer={
          finished ? (
            <Button type="primary" onClick={close}>
              Close
            </Button>
          ) : (
            <Space>
              <Button onClick={close} disabled={running}>
                Cancel
              </Button>
              <Button type="primary" loading={running} disabled={files.length === 0} onClick={run}>
                Upload {files.length || ''} file{files.length === 1 ? '' : 's'}
              </Button>
            </Space>
          )
        }
      >
        <Form form={form} layout="vertical" initialValues={initialValues} disabled={running}>
          {children(form)}
        </Form>
        <Upload.Dragger
          multiple
          accept={rule.accept}
          fileList={files}
          disabled={running}
          showUploadList={false}
          beforeUpload={(file) => {
            if (file.size > rule.maxMB * 1024 * 1024) {
              message.error(`${file.name} is too large. Upload ${rule.hint}.`);
              return Upload.LIST_IGNORE;
            }
            return false;
          }}
          onChange={(e) => setFiles(e.fileList)}
        >
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p className="ant-upload-text">Click or drag files here</p>
          <p className="ant-upload-hint">{rule.hint}. Each file becomes one entry, titled after its file name.</p>
        </Upload.Dragger>
        <Checkbox checked={addToAI} onChange={(e) => setAddToAI(e.target.checked)} disabled={running} style={{ marginTop: 12 }}>
          Also add PDF and Word files to the AI assistant
        </Checkbox>
        {files.length > 0 && (
          <List
            size="small"
            style={{ marginTop: 12, maxHeight: 220, overflow: 'auto' }}
            dataSource={files}
            renderItem={(f) => {
              const s = status[f.uid];
              return (
                <List.Item
                  actions={[
                    !running && !s ? (
                      <Button key="x" type="link" size="small" onClick={() => setFiles((cur) => cur.filter((x) => x.uid !== f.uid))}>
                        Remove
                      </Button>
                    ) : null,
                  ]}
                >
                  <Space orientation="vertical" size={0} style={{ minWidth: 0 }}>
                    <Space>
                      {s?.state === 'working' && <LoadingOutlined />}
                      {s?.state === 'done' && <CheckCircleFilled style={{ color: 'var(--success)' }} />}
                      {s?.state === 'failed' && <CloseCircleFilled style={{ color: 'var(--danger, #dc2626)' }} />}
                      <Typography.Text ellipsis style={{ maxWidth: 380 }}>
                        {f.name}
                      </Typography.Text>
                      {s?.state === 'done' && !s.note && <Tag color="success">Uploaded</Tag>}
                    </Space>
                    {s?.note && <Typography.Text type={s.state === 'failed' ? 'danger' : 'secondary'} style={{ fontSize: 12 }}>{s.note}</Typography.Text>}
                  </Space>
                </List.Item>
              );
            }}
          />
        )}
        {finished && files.some((f) => status[f.uid]?.state === 'failed') && (
          <Alert type="warning" showIcon style={{ marginTop: 12 }} title="Some files were not saved. Fix the problem and upload them again." />
        )}
      </Modal>
    </>
  );
}
