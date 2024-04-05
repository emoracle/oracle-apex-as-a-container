create user test1 identified by test1 default tablespace USERS quota unlimited on USERS;

begin
  --grant all the privileges that a db user would get if provisioned by APEX
  for r_1 in ( select privilege
               from sys.dba_sys_privs
               where grantee = 'APEX_GRANTS_FOR_NEW_USERS_ROLE' 
            ) 
  loop
    execute immediate 'grant '||r_1.privilege||' to TEST1';
  end loop;
     
  apex_instance_admin.add_workspace(
        p_workspace      => 'TESTWS',
        p_primary_schema => 'TEST1');
         
    apex_util.set_workspace(
        p_workspace      => 'TESTWS');
         
    apex_util.create_user(
        p_user_name                    => 'TEST1',
        p_web_password                 => 'TEST1',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_email_address                => 'test1@example.com',
        p_default_schema               => 'TEST1',
        p_change_password_on_first_use => 'N' );
         
    apex_util.set_workspace(
        p_workspace      => 'TESTWS');
end;
/

