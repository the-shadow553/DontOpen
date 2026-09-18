-- Discordia: recursos avançados para mensagens de canais.
-- Execute uma vez no SQL Editor do Supabase, antes de publicar o código desta etapa.

alter table public.messages
    add column if not exists reply_to bigint references public.messages(id) on delete set null,
    add column if not exists attachment_url text,
    add column if not exists attachment_name text,
    add column if not exists edited_at timestamptz;

create table if not exists public.message_reactions (
    message_id bigint not null references public.messages(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    emoji text not null check (char_length(emoji) between 1 and 16),
    created_at timestamptz not null default now(),
    primary key (message_id, user_id, emoji)
);

create index if not exists message_reactions_message_id_idx
    on public.message_reactions(message_id);

alter table public.message_reactions enable row level security;

drop policy if exists "Leitura pública de reações" on public.message_reactions;
create policy "Leitura pública de reações"
on public.message_reactions for select
to authenticated
using (true);

drop policy if exists "Usuário adiciona a própria reação" on public.message_reactions;
create policy "Usuário adiciona a própria reação"
on public.message_reactions for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Usuário remove a própria reação" on public.message_reactions;
create policy "Usuário remove a própria reação"
on public.message_reactions for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Usuário edita a própria mensagem normal" on public.messages;
create policy "Usuário edita a própria mensagem normal"
on public.messages for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Usuário apaga a própria mensagem normal" on public.messages;
create policy "Usuário apaga a própria mensagem normal"
on public.messages for delete
to authenticated
using ((select auth.uid()) = user_id);
