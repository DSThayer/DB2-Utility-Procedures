---------------------------------------------------------------------------------------------------
--logging_functions.sql
--
--Dan Thayer
--
--Copyright 2017 Swansea University
--
--Licensed under the Apache License, Version 2.0 (the "License");
--you may not use this file except in compliance with the License.
--You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
--Unless required by applicable law or agreed to in writing, software
--distributed under the License is distributed on an "AS IS" BASIS,
--WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--See the License for the specific language governing permissions and
--limitations under the License.
--
---------------------------------------------------------------------------------------------------
--
--A set of utilities for logging actions and reporting errors to a table within stored procedures
--that we develop in DB2 sql.


--A stack that keeps track of what procedure we are in.
--Allows logging of nested procedure calls without loss of state.
--The actual session table is created by the log_start() procedure. However,
--it has to be defined here as well to allow the procedures to compile.
declare global temporary table session.fn_stack (
	fn 				char(50),
	log_table		char(200),
	stack_level 	integer
) with replace on commit preserve rows!

--Call this to put a message in the log.
drop specific procedure fnc.log_msg!
create procedure fnc.log_msg (message VARCHAR(1000))
specific fnc.log_msg
modifies sql data
language sql
begin 
	declare v_sql varchar(2000);
	declare levels	integer;
	declare curr_log_table varchar(200);
	declare fn_disp varchar(50);
	declare fn		varchar(50);
	
	set (fn,curr_log_table,levels) = (
		select fn,log_table,stack_level
			from session.fn_stack
			where stack_level = (select max(stack_level) from session.fn_stack)
	);
	
	if levels + length(strip(fn)) > 51 then
		set fn_disp = char(repeat('>',levels-1) || fn, 47) || '...';
	else
		set fn_disp = repeat('>',levels-1) || fn;
	end if;
	
	if curr_log_table is not null then
		set v_sql = 'insert into ' || curr_log_table || ' values (CURRENT TIMESTAMP,''' || fn_disp ||
			''',current schema,'''||message||''')';
		execute immediate v_sql;
	else
		signal sqlstate value 'AAZ01' 
			set message_text = 'Attempted to call log_msg() without first calling log_start()';
	end if;
end!

--A version of the log message procedure that commits the current transaction.
drop specific procedure fnc.log_msg_commit!
create procedure fnc.log_msg_commit (message VARCHAR(1000))
specific fnc.log_msg_commit
modifies sql data
language sql
begin 
    call fnc.log_msg(message);
    commit;
end!





--Call this at the start of a procedure or function.
drop specific procedure fnc.log_start!
create procedure fnc.log_start (
	function_name VARCHAR(50),
	log_table VARCHAR(200)
)
specific fnc.log_start
modifies sql data
language sql
begin
	declare v_sql varchar(1000);
	declare table_existed    integer default 0;
	declare fn_stack_missing integer default 0;
	
	declare fn_stack_does_not_exist condition for sqlstate '42704';
	declare table_already_exists condition for sqlstate '42710';

	declare continue handler for fn_stack_does_not_exist set fn_stack_missing = 1;
	
	declare continue handler for table_already_exists set table_existed = 1;
	
	--A dummy statement that returns an error if the procedure call stack table does not exist.
	set v_sql = 'delete from session.fn_stack where 1=0';
	execute immediate v_sql;
	
	if fn_stack_missing = 1 then 
		declare global temporary table session.fn_stack (
			fn 				char(50),
			log_table		char(200),
			stack_level 	integer
		) with replace on commit preserve rows;
	end if;

	set v_sql = 'create table ' || log_table || '( timestamp VARCHAR(50),' ||
		'function VARCHAR(50), schema VARCHAR(50), message VARCHAR(1000))';
	execute immediate v_sql;

	insert into session.fn_stack values	(
		function_name,
		log_table,
		coalesce((select max(stack_level) from session.fn_stack),0)+1
	);

	
	if table_existed = 0 then
		call fnc.log_msg('Log table did not exist: created.');
	end if;

	call fnc.log_msg('Procedure started.');
end!


--Call this to put a message in the log and cancel execution with an error.
--The error message is truncated by DB2 to considerably less than 200 characters. 
drop specific procedure fnc.log_die!
create procedure fnc.log_die (message VARCHAR(200))
specific fnc.log_die
modifies sql data
language sql
begin 
	call fnc.log_msg(message);
	--Delete the entire call stack, as this error will interrupt all procedures.
	--In the future, perhaps error trapping could be introduced, in which case 
	--this logic should be revisited.
	delete from session.fn_stack;
	SIGNAL SQLSTATE VALUE 'AAZ01' SET MESSAGE_TEXT = message;
end!

--Call this when a procedure or function finishes successfully.
drop specific procedure fnc.log_finish!
create procedure fnc.log_finish ()
specific fnc.log_finish
modifies sql data
language sql
begin 
	call fnc.log_msg('Procedure completed.');
	
	--Remove top function from stack.
	delete from session.fn_stack
		where stack_level = (select max(stack_level) as curr_height from session.fn_stack);
end!
