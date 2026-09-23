-- Execute esta correção UMA vez no SQL Editor do Supabase.
-- Ela resolve o erro de RLS ao criar servidor: o banco define o dono pela sessão atual.

create or replace function public.enforce_one_server_per_year()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    new.owner_id := auth.uid();
    if new.owner_id is null then
        raise exception 'Faça login para criar um servidor.';
    end if;
    perform pg_advisory_xact_lock(hashtext(new.owner_id::text || extract(year from now())::text));
    if exists (
        select 1 from public.servers
        where owner_id = new.owner_id
          and created_at >= date_trunc('year', now())
    ) then
        raise exception 'Cada pessoa pode criar apenas um servidor por ano.';
    end if;
    return new;
end;
$$;

drop trigger if exists server_one_per_year on public.servers;
create trigger server_one_per_year before insert on public.servers
for each row execute function public.enforce_one_server_per_year();

drop policy if exists "Usuário cria servidor" on public.servers;
create policy "Usuário cria servidor" on public.servers for insert to authenticated
with check (owner_id = auth.uid());
