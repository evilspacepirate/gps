-----------------------------------------------------------------------
--              GtkAda - Ada95 binding for Gtk+/Gnome                --
--                                                                   --
--                     Copyright (C) 2001                            --
--                         ACT-Europe                                --
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

--  <description>
--  This package provides a high-level text view extended to support
--  many functionalities related to source code editing.
--  </description>

with Gdk.GC;
with Gdk.Font;
with Gtk.Text_View;
with Pango.Font;
with Src_Editor_Buffer;

package Src_Editor_View is

   type Source_View_Record is new Gtk.Text_View.Gtk_Text_View_Record
     with private;
   type Source_View is access all Source_View_Record'Class;

   procedure Gtk_New
     (View              : out Source_View;
      Buffer            : Src_Editor_Buffer.Source_Buffer := null;
      Font              : Pango.Font.Pango_Font_Description := null;
      Show_Line_Numbers : Boolean := False);
   --  Create a new Source_View from the given parameters.
   --  If no Buffer is given, then a new one will be created. For tasks such
   --  as source code edition, it is recommended to specify a fixed-width font,
   --  as the default font used when not specified is proportional (which means
   --  that 'i's will be smaller than 'm's for instance).
   --
   --  If requested, the line numbers are displayed in a small area on
   --  the left of the text view.

   procedure Initialize
     (View              : access Source_View_Record;
      Buffer            : Src_Editor_Buffer.Source_Buffer;
      Font              : Pango.Font.Pango_Font_Description;
      Show_Line_Numbers : Boolean);
   --  Internal initialization procedure.
   --  See the section "Creating your own widgets" in the documentation.

   procedure Set_Font
     (View : access Source_View_Record;
      Font : Pango.Font.Pango_Font_Description);
   --  Change the font used in the given Source_View. Note that this service
   --  should not be used if the widget is not realized.

   procedure Set_Show_Line_Numbers
     (View         : access Source_View_Record;
      Show_Numbers : Boolean := True);
   --  Set whether the line numbers should be displayed or not.

   function Get_Show_Line_Numbers
     (View : access Source_View_Record) return Boolean;
   --  Returns True if the line numbers are displayed.

   procedure Scroll_To_Cursor_Location (View : access Source_View_Record);
   --  Scroll the Source View if the position of the insert cursor is not
   --  within the part of the text currently visible.

private

   type Source_View_Record is new Gtk.Text_View.Gtk_Text_View_Record with
   record
      Pango_Font        : Pango.Font.Pango_Font_Description;
      Font              : Gdk.Font.Gdk_Font;
      Line_Numbers_GC   : Gdk.GC.Gdk_GC;
      Show_Line_Numbers : Boolean;
      LNA_Width_In_Digits : Natural;
   end record;

end Src_Editor_View;
