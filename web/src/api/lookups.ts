import { useQuery } from '@tanstack/react-query';
import { classesApi, mastersApi, staffApi, type AcademicYear, type Department, type Semester, type Subject, type YearLevel } from './phase2';

// Cached dropdown data shared by every page.
const long = { staleTime: 5 * 60_000 };

export const useDepartments = () =>
  useQuery({ queryKey: ['lookup', 'departments'], queryFn: () => mastersApi.all<Department>('departments'), ...long });
export const useAcademicYears = () =>
  useQuery({ queryKey: ['lookup', 'academic-years'], queryFn: () => mastersApi.all<AcademicYear>('academic-years'), ...long });
export const useYearLevels = () =>
  useQuery({ queryKey: ['lookup', 'year-levels'], queryFn: () => mastersApi.all<YearLevel>('year-levels'), ...long });
export const useSemesters = () =>
  useQuery({ queryKey: ['lookup', 'semesters'], queryFn: () => mastersApi.all<Semester>('semesters'), ...long });
export const useSubjects = () =>
  useQuery({ queryKey: ['lookup', 'subjects'], queryFn: () => mastersApi.all<Subject>('subjects'), ...long });
export const useStaffOptions = () =>
  useQuery({ queryKey: ['staff', 'options'], queryFn: () => staffApi.list({ page: 1, page_size: 1000, all: true }).then((r) => r.data) });
export const useClasses = (department_id?: number, academic_year_id?: number | 'all') =>
  useQuery({ queryKey: ['classes', department_id ?? null, academic_year_id ?? null], queryFn: () => classesApi.list({ department_id, academic_year_id }) });
