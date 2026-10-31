-- 提琴先生・排課系統：Supabase 資料庫設定
-- 使用方式：Supabase 後台 → SQL Editor → 貼上整份 → Run（可重複執行，不會報「已存在」）

create extension if not exists btree_gist;

-- ========== 資料表 ==========
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'none' check (role in ('none','admin','staff','teacher')),
  teacher_id text            -- 角色為 teacher 時，對應 teachers.id
);

create table if not exists public.teachers (
  id text primary key,
  name text not null,
  inst text[] not null default '{}'
);

create table if not exists public.students (
  id text primary key,
  name text not null,
  teacher_ids text[] not null default '{}'   -- 指導老師
);
-- 舊資料庫補欄位（可重複執行）
alter table public.students add column if not exists teacher_ids text[] not null default '{}';

-- 課時費獨立存放，只有管理者讀得到
create table if not exists public.student_rates (
  student_id text primary key references public.students(id) on delete cascade,
  rate1 numeric,
  rate_g numeric
);

create table if not exists public.lessons (
  id text primary key,
  lesson_date date not null,
  start_min int not null check (start_min between 480 and 1410),   -- 8:00 起，分鐘數
  dur int not null check (dur > 0),
  room text not null check (room in ('A','B','C')),
  teacher_id text references public.teachers(id) on delete cascade,
  students text[] not null default '{}',
  inst text not null check (inst in ('鋼琴','小提琴','大提琴','其他課程','出租')),
  check (start_min + dur <= 1440),
  check (cardinality(students) >= 1),
  check (inst = '出租' or teacher_id is not null),
  check (inst <> '鋼琴' or room in ('A','C')),                       -- 鋼琴課只能 A、C
  check (inst = '出租' or cardinality(students) <= 1 or room = 'C'),  -- 團體班只能 C
  -- 同一天同一時段：同一琴房不能重複
  constraint no_room_overlap exclude using gist
    (room with =, lesson_date with =, int4range(start_min, start_min + dur) with &&),
  -- 同一老師不能重複
  constraint no_teacher_overlap exclude using gist
    (teacher_id with =, lesson_date with =, int4range(start_min, start_min + dur) with &&)
    where (teacher_id is not null)
);

-- 同一學生不能重複（學生存在陣列裡，用觸發器檢查）
create or replace function public.check_student_overlap() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from public.lessons l
    where l.id <> new.id
      and l.lesson_date = new.lesson_date
      and l.students && new.students
      and int4range(l.start_min, l.start_min + l.dur) && int4range(new.start_min, new.start_min + new.dur)
  ) then
    raise exception '學生在該時段已有其他課程' using errcode = '23P01';
  end if;
  return new;
end $$;

drop trigger if exists lessons_student_overlap on public.lessons;
create trigger lessons_student_overlap
before insert or update on public.lessons
for each row execute function public.check_student_overlap();

-- ========== 登入後自動建立 profile（預設無權限，需管理者開通）==========
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ========== 權限（Row Level Security）==========
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.my_teacher() returns text
language sql stable security definer set search_path = public as
$$ select teacher_id from public.profiles where id = auth.uid() $$;

alter table public.profiles       enable row level security;
alter table public.teachers       enable row level security;
alter table public.students       enable row level security;
alter table public.student_rates  enable row level security;
alter table public.lessons        enable row level security;

-- profiles：自己看自己，管理者可看全部與修改
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select
  using (id = auth.uid() or public.my_role() = 'admin');
drop policy if exists profiles_admin on public.profiles;
create policy profiles_admin on public.profiles for update
  using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

-- teachers：管理者／櫃檯全看；老師只看自己
drop policy if exists teachers_read on public.teachers;
create policy teachers_read on public.teachers for select
  using (public.my_role() in ('admin','staff') or id = public.my_teacher());
drop policy if exists teachers_write on public.teachers;
create policy teachers_write on public.teachers for all
  using (public.my_role() in ('admin','staff')) with check (public.my_role() in ('admin','staff'));

-- students：管理者／櫃檯全看；老師只看自己課堂上的學生
drop policy if exists students_read on public.students;
create policy students_read on public.students for select
  using (public.my_role() in ('admin','staff')
         or exists (select 1 from public.lessons l
                    where l.teacher_id = public.my_teacher() and l.students @> array[students.id]));
drop policy if exists students_write on public.students;
create policy students_write on public.students for all
  using (public.my_role() in ('admin','staff')) with check (public.my_role() in ('admin','staff'));

-- lessons：管理者／櫃檯全看可改；老師只看自己的課，不能改
drop policy if exists lessons_read on public.lessons;
create policy lessons_read on public.lessons for select
  using (public.my_role() in ('admin','staff') or teacher_id = public.my_teacher());
drop policy if exists lessons_write on public.lessons;
create policy lessons_write on public.lessons for all
  using (public.my_role() in ('admin','staff')) with check (public.my_role() in ('admin','staff'));

-- 課時費：只有管理者
drop policy if exists rates_admin on public.student_rates;
create policy rates_admin on public.student_rates for all
  using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

-- ========== 即時同步 ==========
do $$ declare t text; begin
  foreach t in array array['teachers','students','lessons'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null; end;
  end loop;
end $$;

-- ========== 建立第一位管理者 ==========
-- 1) 先到 Authentication → Users → Add user 建立帳號（勾選 Auto Confirm User）
-- 2) 再執行下面這行（把信箱換成你的）：
-- update public.profiles set role = 'admin' where email = 'you@example.com';
--
-- 開通櫃檯：  update public.profiles set role = 'staff' where email = '...';
-- 開通老師：  先在系統「老師與學生」新增該老師，執行 select id, name from public.teachers; 取得 id，再：
--             update public.profiles set role = 'teacher', teacher_id = '老師的id' where email = '...';
