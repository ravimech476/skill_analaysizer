import { useState, type ReactNode } from 'react';
import { Avatar, Button, Popconfirm, Space, Tooltip, Typography, Upload, message } from 'antd';
import { DeleteOutlined, FileImageOutlined, FilePdfOutlined, UploadOutlined } from '@ant-design/icons';
import { errorMessage } from '../api/client';
import { FILE_RULES, fileUrl, filesApi, type FileCategory, type FileLink, type UploadedFile } from '../api/files';
import { series } from '../theme';

/** A stable colour per person, so initials in a list are easy to tell apart. */
function avatarColor(name = '') {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) % 997;
  return series[hash % series.length];
}

/** Round avatar: the photo when there is one, otherwise initials on a soft tint. */
export function UserAvatar({ name, photo, size = 'default' }: { name?: string; photo?: FileLink | null; size?: number | 'small' | 'default' | 'large' }) {
  const c = avatarColor(name);
  return (
    <Avatar size={size} src={photo ? fileUrl(photo) : undefined} style={photo ? undefined : { background: `${c}1f`, color: c, fontWeight: 600 }}>
      {name?.charAt(0).toUpperCase()}
    </Avatar>
  );
}

/** Opens a stored file in a new tab. */
export function FileAnchor({ link, label, icon = true }: { link: FileLink; label?: ReactNode; icon?: boolean }) {
  const isPdf = link.type === 'application/pdf';
  return (
    <Typography.Link href={fileUrl(link)} target="_blank" rel="noreferrer">
      {icon && (isPdf ? <FilePdfOutlined /> : <FileImageOutlined />)} {label ?? link.name}
    </Typography.Link>
  );
}

/** Checks size before sending; the server still validates type and size. */
function precheck(category: FileCategory, file: File) {
  const rule = FILE_RULES[category];
  if (file.size > rule.maxMB * 1024 * 1024) {
    message.error(`That file is too large. Upload ${rule.hint}.`);
    return false;
  }
  return true;
}

/** A button that uploads one file of a category and hands back the stored file. */
export function UploadButton({
  category,
  onUploaded,
  children = 'Upload',
  size,
  type,
  disabled,
}: {
  category: FileCategory;
  onUploaded: (f: UploadedFile) => Promise<unknown> | void;
  children?: ReactNode;
  size?: 'small' | 'middle';
  type?: 'primary' | 'default';
  disabled?: boolean;
}) {
  const [busy, setBusy] = useState(false);
  return (
    <Upload
      accept={FILE_RULES[category].accept}
      showUploadList={false}
      disabled={disabled || busy}
      beforeUpload={(file) => {
        if (!precheck(category, file)) return Upload.LIST_IGNORE;
        setBusy(true);
        filesApi
          .upload(category, file)
          .then((f) => onUploaded(f))
          .catch((e) => message.error(errorMessage(e)))
          .finally(() => setBusy(false));
        return false;
      }}
    >
      <Tooltip title={FILE_RULES[category].hint}>
        <Button size={size} type={type} icon={<UploadOutlined />} loading={busy} disabled={disabled}>
          {children}
        </Button>
      </Tooltip>
    </Upload>
  );
}

/**
 * One file slot (resume, JD, offer letter, logo…): shows the current file and, when editable,
 * lets the user upload a replacement or remove it. `save` stores the new file id (or null).
 */
export function FileSlot({
  category,
  value,
  canEdit,
  save,
  emptyText = 'Not uploaded',
  uploadLabel = 'Upload',
}: {
  category: FileCategory;
  value: FileLink | null | undefined;
  canEdit: boolean;
  save: (fileId: number | null) => Promise<unknown>;
  emptyText?: string;
  uploadLabel?: string;
}) {
  const [removing, setRemoving] = useState(false);
  const run = (id: number | null) =>
    save(id).then(
      () => message.success(id ? 'File saved' : 'File removed'),
      (e) => message.error(errorMessage(e)),
    );
  return (
    <Space wrap size={[8, 4]}>
      {value ? <FileAnchor link={value} /> : <Typography.Text type="secondary">{emptyText}</Typography.Text>}
      {canEdit && (
        <>
          <UploadButton size="small" category={category} onUploaded={(f) => run(f.id)}>
            {value ? 'Replace' : uploadLabel}
          </UploadButton>
          {value && (
            <Popconfirm
              title="Remove this file?"
              onConfirm={() => {
                setRemoving(true);
                return run(null).finally(() => setRemoving(false));
              }}
            >
              <Button size="small" danger icon={<DeleteOutlined />} loading={removing} />
            </Popconfirm>
          )}
        </>
      )}
    </Space>
  );
}
