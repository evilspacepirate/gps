-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2003-2004                       --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Unicode.CES;
with XML_Gtk.Readers;

package body XML_Parsers is
   package Gtk_Readers is new XML_Gtk.Readers (Glib.Gint, 0, Glib.Xml_Int);
   use Gtk_Readers;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (File  : String;
      Tree  : out Glib.Xml_Int.Node_Ptr;
      Error : out GNAT.OS_Lib.String_Access)
   is
      Err : Unicode.CES.Byte_Sequence_Access;
   begin
      Gtk_Readers.Parse (File, Tree, Err);
      Error := GNAT.OS_Lib.String_Access (Err);
   end Parse;

end XML_Parsers;
