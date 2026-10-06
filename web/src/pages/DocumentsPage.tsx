import { useState } from 'react';
import dayjs from 'dayjs';
import { Button, Card, Segmented, Select, Space, Table, Tag, Typography, message } from 'antd';
import { CheckOutlined, CloseOutlined } from '@ant-design/icons';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { DOC_STATUS_COLOR, documentsApi, type StudentDocument } from '../api/files';
import { useClasses } from '../api/lookups';
import { FileAnchor } from '../components/Files';
import { rejectDocument } from '../components/StudentDocuments';

/** Staff verification queue for student documents (HOD/staff: own department). */
export default function DocumentsPage() {
  const qc = useQueryClient();
  const { data: classes } = useClasses();
  const [status, setStatus] = useState('pending');
  const [classId, setClassId] = useState<number>();
  const [page, setPage] = useState(1);
  const params = { status, class_id: classId, page, page_size: 20 };
  const { data, isFetching } = useQuery({ queryKey: ['documents-queue', params], queryFn: () => documentsApi.queue(params), placeholderData: keepPreviousData });
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['documents-queue'] });
    qc.invalidateQueries({ queryKey: ['documents'] });
  };
  const verify = useMutation({
    mutationFn: (d: StudentDocument) => documentsApi.review(d.student_id, d.id, { status: 'verified' }),
    onSuccess: () => {
      message.success('Verified');
      refresh();
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <Card
      title="Student documents"
      extra={
        <Space wrap>
          <Select
            allowClear
            style={{ width: 170 }}
            placeholder="All classes"
            value={classId}
            onChange={(v) => {
              setClassId(v);
              setPage(1);
            }}
            options={(classes ?? []).map((c) => ({ value: c.id, label: c.label }))}
          />
          <Segmented
            value={status}
            onChange={(v) => {
              setStatus(v as string);
              setPage(1);
            }}
            options={[
              { value: 'pending', label: 'To verify' },
              { value: 'verified', label: 'Verified' },
              { value: 'rejected', label: 'Rejected' },
              { value: 'all', label: 'All' },
            ]}
          />
        </Space>
      }
    >
      <Table<StudentDocument>
        rowKey="id"
        size="small"
        loading={isFetching}
        dataSource={data?.data}
        scroll={{ x: 760 }}
        pagination={{ current: page, pageSize: 20, total: data?.meta.total, onChange: setPage, hideOnSinglePage: true }}
        locale={{ emptyText: status === 'pending' ? 'Nothing waiting for verification' : 'No documents' }}
        columns={[
          {
            title: 'Student',
            render: (_, d) => (
              <Space orientation="vertical" size={0}>
                <span>{d.student_name}</span>
                <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                  {d.register_no}
                  {d.class_label ? ` · ${d.class_label}` : ''}
                </Typography.Text>
              </Space>
            ),
          },
          {
            title: 'Document',
            render: (_, d) => (
              <Space orientation="vertical" size={0}>
                {d.file ? <FileAnchor link={d.file} label={d.title} /> : d.title}
                <Typography.Text type="secondary" style={{ fontSize: 12 }}>{d.doc_type_label}</Typography.Text>
              </Space>
            ),
          },
          { title: 'Uploaded', dataIndex: 'created_at', width: 130, render: (v) => dayjs(v).format('DD MMM, HH:mm') },
          {
            title: 'Status',
            width: 160,
            render: (_, d) => (
              <Space orientation="vertical" size={0}>
                <Tag color={DOC_STATUS_COLOR[d.status]}>{d.status}</Tag>
                {d.status === 'rejected' && d.remarks && <Typography.Text type="danger" style={{ fontSize: 12 }}>{d.remarks}</Typography.Text>}
              </Space>
            ),
          },
          {
            title: '',
            width: 190,
            align: 'right',
            render: (_, d) => (
              <Space>
                {d.status !== 'verified' && (
                  <Button size="small" icon={<CheckOutlined />} loading={verify.isPending && verify.variables?.id === d.id} onClick={() => verify.mutate(d)}>
                    Verify
                  </Button>
                )}
                {d.status !== 'rejected' && (
                  <Button size="small" danger icon={<CloseOutlined />} onClick={() => rejectDocument(d, refresh)}>
                    Reject
                  </Button>
                )}
              </Space>
            ),
          },
        ]}
      />
    </Card>
  );
}
