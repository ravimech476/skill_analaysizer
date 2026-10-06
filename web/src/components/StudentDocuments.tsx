import { useState } from 'react';
import dayjs from 'dayjs';
import { Alert, Button, Empty, Input, Modal, Popconfirm, Select, Space, Table, Tag, Typography, message } from 'antd';
import { CheckOutlined, CloseOutlined, DeleteOutlined, PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { DOC_STATUS_COLOR, documentsApi, type StudentDocument } from '../api/files';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { FileAnchor, UploadButton } from './Files';

/** Ask for a rejection reason, then reject. */
export function rejectDocument(doc: StudentDocument, onDone: () => void) {
  let reason = '';
  Modal.confirm({
    title: `Reject ${doc.title}?`,
    content: <Input.TextArea autoFocus rows={3} placeholder="Reason (the student sees this)" onChange={(e) => (reason = e.target.value)} />,
    okText: 'Reject',
    okButtonProps: { danger: true },
    onOk: async () => {
      if (!reason.trim()) {
        message.error('Give a reason');
        throw new Error('reason required');
      }
      try {
        await documentsApi.review(doc.student_id, doc.id, { status: 'rejected', remarks: reason.trim() });
        message.success('Document rejected; the student has been told');
        onDone();
      } catch (e) {
        message.error(errorMessage(e));
        throw e;
      }
    },
  });
}

/** Documents a student keeps on file. Students add their own; staff add, verify, reject and delete. */
export default function StudentDocuments({ studentId }: { studentId: number }) {
  const { user, can } = useAuth();
  const qc = useQueryClient();
  const audience = audienceOf(user?.roles ?? []);
  const isStaff = audience === 'admin' || audience === 'staff';
  const isSelf = user?.id === studentId;
  const canAdd = can('document.create') && (isSelf || isStaff);
  const canReview = isStaff && can('document.verify');
  const key = ['documents', studentId];
  const { data, isLoading, error } = useQuery({ queryKey: key, queryFn: () => documentsApi.list(studentId) });
  const [draft, setDraft] = useState<{ doc_type?: string; title: string }>({ title: '' });
  const refresh = () => {
    qc.invalidateQueries({ queryKey: key });
    qc.invalidateQueries({ queryKey: ['documents-queue'] });
  };

  const verify = useMutation({
    mutationFn: (d: StudentDocument) => documentsApi.review(studentId, d.id, { status: 'verified' }),
    onSuccess: () => {
      message.success('Verified');
      refresh();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const remove = useMutation({
    mutationFn: (d: StudentDocument) => documentsApi.remove(studentId, d.id),
    onSuccess: refresh,
    onError: (e) => message.error(errorMessage(e)),
  });

  if (error) return <Alert type="error" showIcon title={errorMessage(error)} />;
  const types = data?.types ?? {};

  return (
    <Space orientation="vertical" style={{ width: '100%' }}>
      {canAdd && (
        <Space wrap>
          <Select
            style={{ width: 220 }}
            placeholder="Document type"
            value={draft.doc_type}
            onChange={(doc_type) => setDraft((d) => ({ ...d, doc_type }))}
            options={Object.entries(types)
              .sort((a, b) => a[1].localeCompare(b[1]))
              .map(([value, label]) => ({ value, label }))}
          />
          <Input style={{ width: 220 }} placeholder="Title (optional)" maxLength={150} value={draft.title} onChange={(e) => setDraft((d) => ({ ...d, title: e.target.value }))} />
          <UploadButton
            category="student_document"
            type="primary"
            disabled={!draft.doc_type}
            onUploaded={(f) =>
              documentsApi.add(studentId, { doc_type: draft.doc_type!, title: draft.title || undefined, file_id: f.id }).then(() => {
                message.success(isStaff && !isSelf ? 'Document added and marked verified' : 'Document uploaded; staff will verify it');
                setDraft({ title: '' });
                refresh();
              })
            }
          >
            <PlusOutlined /> Add document
          </UploadButton>
        </Space>
      )}
      <Table<StudentDocument>
        rowKey="id"
        size="small"
        loading={isLoading}
        dataSource={data?.documents}
        pagination={false}
        scroll={{ x: 640 }}
        locale={{ emptyText: <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="No documents on file" /> }}
        columns={[
          {
            title: 'Document',
            render: (_, d) => (
              <Space orientation="vertical" size={0}>
                {d.file ? <FileAnchor link={d.file} label={d.title} /> : d.title}
                <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                  {d.doc_type_label} · uploaded {dayjs(d.created_at).format('DD MMM YYYY')}
                  {d.uploaded_by ? ` by ${d.uploaded_by}` : ''}
                </Typography.Text>
              </Space>
            ),
          },
          {
            title: 'Status',
            width: 220,
            render: (_, d) => (
              <Space orientation="vertical" size={0}>
                <Tag color={DOC_STATUS_COLOR[d.status]}>{d.status}</Tag>
                {d.verified_by && (
                  <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                    by {d.verified_by}
                    {d.verified_at ? `, ${dayjs(d.verified_at).format('DD MMM')}` : ''}
                  </Typography.Text>
                )}
                {d.status === 'rejected' && d.remarks && <Typography.Text type="danger" style={{ fontSize: 12 }}>{d.remarks}</Typography.Text>}
              </Space>
            ),
          },
          {
            title: '',
            width: 200,
            align: 'right',
            render: (_, d) => (
              <Space>
                {canReview && d.status !== 'verified' && (
                  <Button size="small" icon={<CheckOutlined />} loading={verify.isPending && verify.variables?.id === d.id} onClick={() => verify.mutate(d)}>
                    Verify
                  </Button>
                )}
                {canReview && d.status !== 'rejected' && (
                  <Button size="small" danger icon={<CloseOutlined />} onClick={() => rejectDocument(d, refresh)}>
                    Reject
                  </Button>
                )}
                {((isStaff && can('document.delete')) || (isSelf && d.status !== 'verified')) && (
                  <Popconfirm title="Delete this document?" onConfirm={() => remove.mutateAsync(d)}>
                    <Button size="small" type="text" danger icon={<DeleteOutlined />} />
                  </Popconfirm>
                )}
              </Space>
            ),
          },
        ]}
      />
    </Space>
  );
}
