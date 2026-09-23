-- Discordia: figurinhas pessoais.
-- Execute uma vez no SQL Editor do Supabase.
-- As imagens usam o bucket chat-files que o projeto já utiliza para anexos.

create table if not exists public.user_stickers (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null check (char_length(trim(name)) between 1 and 40),
    image_url text not null,
    created_at timestamptz not null default now()
);

create index if not exists user_stickers_owner_idx on public.user_stickers(user_id, created_at);
alter table public.user_stickers enable row level security;

drop policy if exists "Usuários leem figurinhas" on public.user_stickers;
create policy "Usuários leem figurinhas" on public.user_stickers
for select to authenticated using (true);

drop policy if exists "Usuário cria a própria figurinha" on public.user_stickers;
create policy "Usuário cria a própria figurinha" on public.user_stickers
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "Usuário apaga a própria figurinha" on public.user_stickers;
create policy "Usuário apaga a própria figurinha" on public.user_stickers
for delete to authenticated using (user_id = auth.uid());
