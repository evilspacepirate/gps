-----------------------------------------------------------------------
--                           GLIDE II                                --
--                     Copyright (C) 2001                            --
--                          ACT-Europe                               --
--                                                                   --
-- This library is free software; you can redistribute it and/or     --
-- modify it under the terms of the GNU General Public               --
-- License as published by the Free Software Foundation; either      --
-- version 2 of the License, or (at your option) any later version.  --
--                                                                   --
-- This library is distributed in the hope that it will be useful,   --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of    --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details.                          --
--                                                                   --
-- You should have received a copy of the GNU General Public         --
-- License along with this library; if not, write to the             --
-- Free Software Foundation, Inc., 59 Temple Place - Suite 330,      --
-- Boston, MA 02111-1307, USA.                                       --
--                                                                   --
-- As a special exception, if other files instantiate generics from  --
-- this unit, or you link this unit with other files to produce an   --
-- executable, this  unit  does not  by itself cause  the resulting  --
-- executable to be covered by the GNU General Public License. This  --
-- exception does not however invalidate any other reasons why the   --
-- executable file  might be covered by the  GNU Public License.     --
-----------------------------------------------------------------------

--  This package provides a P4 object implementating the VCS abstract
--  specification.
--
--  See package VCS for a complete spec of this package.

with Basic_Types;    use Basic_Types;

package VCS.P4 is

   type P4_Record is new VCS_Record with private;
   --  A value used to reference a P4 repository.

   type P4_Access is access all P4_Record'Class;

   function Get_Status
     (Rep         : access P4_Record;
      Filenames   : String_List.List;
      Get_Status  : Boolean          := True;
      Get_Version : Boolean          := True;
      Get_Tags    : Boolean          := False;
      Get_Users   : Boolean          := False)
     return File_Status_List.List;

   function Local_Get_Status
     (Rep         : access P4_Record;
      Filenames   :        String_List.List)
     return File_Status_List.List;

   procedure Open
     (Rep       : access P4_Record;
      Name      : String;
      User_Name : String := "");

   procedure Commit
     (Rep  : access P4_Record;
      Name : String;
      Log  : String);

   procedure Update (Rep : access P4_Record; Name : String);

   procedure Merge (Rep : access P4_Record; Name : String);

   procedure Add (Rep : access P4_Record; Name : String);

   procedure Remove (Rep : access P4_Record; Name : String);

   function Diff
     (Rep       : access P4_Record;
      File_Name : String;
      Version_1 : String := "";
      Version_2 : String)
     return String_List.List;

   function Log
      (Rep       : access P4_Record;
       File_Name : String)
      return String_List.List;

   function Success (Rep : access P4_Record) return Boolean;

   function Get_Message (Rep : access P4_Record) return String;

private
   type P4_Record is new VCS_Record with record
      Success : Boolean := False;
      Message : String_Access;
   end record;
end VCS.P4;
