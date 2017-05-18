---------------------------------------------------------------------------------------------------
--drop_index_if_exists.sql
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
--A utility to drop an index if it exists, or fail silently if it does not exist.
--
--usage:
--
--call fnc.drop_index_if_exists('schema.tablename')
--

drop specific procedure fnc.drop_index_if_exists!
create procedure fnc.drop_index_if_exists (
	indexname VARCHAR(1000)
)
specific fnc.drop_index_if_exists
modifies sql data
language sql
begin
	declare do_nothing integer default 0;
	declare table_doesnt_exist condition for sqlstate '42704';
	declare continue handler for table_doesnt_exist set do_nothing = 1;
	
	execute immediate 'drop index ' || indexname;	
end!