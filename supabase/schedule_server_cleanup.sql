-- EXECUTE UMA VEZ depois de executar servers.sql.
-- No Supabase, ative a extensão pg_cron em Database > Extensions se ela não estiver ativa.
-- Esta tarefa roda todos os dias às 04:00 e exclui servidores 30 dias inativos.

select cron.schedule(
    'discordia-remove-servers-inactive-30-days',
    '0 4 * * *',
    $$select public.delete_inactive_servers();$$
);
