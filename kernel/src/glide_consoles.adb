-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2001-2002                       --
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

with Glib;                     use Glib;
with Gdk.Color;                use Gdk.Color;
with Gtk.Adjustment;           use Gtk.Adjustment;
with Gtk.Enums;                use Gtk.Enums;
with Gtk.Scrolled_Window;      use Gtk.Scrolled_Window;
with Gtk.Text;                 use Gtk.Text;
with Gtk.Widget;               use Gtk.Widget;
with Gtkada.Handlers;          use Gtkada.Handlers;

with Glide_Result_View;        use Glide_Result_View;
with Glide_Kernel;             use Glide_Kernel;
with Glide_Kernel.Modules;     use Glide_Kernel.Modules;
with Glide_Kernel.Preferences; use Glide_Kernel.Preferences;
with Traces;                   use Traces;

with GNAT.Regpat;              use GNAT.Regpat;
with GNAT.OS_Lib;              use GNAT.OS_Lib;

package body Glide_Consoles is

   Me : constant Debug_Handle := Create ("Glide_Console");

   function On_Button_Release
     (Widget : access Gtk_Widget_Record'Class) return Boolean;
   --  Handler for "button_press_event" signal

   -----------
   -- Clear --
   -----------

   procedure Clear (Console : access Glide_Console_Record) is
   begin
      Delete_Text (Console.Text);
   end Clear;

   ---------------
   -- Get_Chars --
   ---------------

   function Get_Chars (Console : access Glide_Console_Record) return String is
   begin
      return Get_Chars (Console.Text);
   end Get_Chars;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Console : out Glide_Console;
      Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class) is
   begin
      Console := new Glide_Console_Record;
      Initialize (Console, Kernel);
   end Gtk_New;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Console : access Glide_Console_Record'Class;
      Kernel  : access Glide_Kernel.Kernel_Handle_Record'Class) is
   begin
      Gtk.Scrolled_Window.Initialize (Console);
      Console.Kernel := Kernel_Handle (Kernel);

      Set_Policy (Console, Policy_Never, Policy_Always);
      Set_Size_Request (Console, -1, 100);

      Gtk_New (Console.Text);
      Set_Editable (Console.Text, False);
      Add (Console, Console.Text);

      Return_Callback.Object_Connect
        (Console.Text, "button_release_event",
         Return_Callback.To_Marshaller (On_Button_Release'Access), Console);
   end Initialize;

   ------------
   -- Insert --
   ------------

   procedure Insert
     (Console             : access Glide_Console_Record;
      Text                : String;
      Highlight_Sloc      : Boolean := True;
      Add_LF              : Boolean := True;
      Mode                : Message_Type := Info;
      Location_Identifier : String := "")
   is
      File_Location : constant Pattern_Matcher :=
        Compile (Get_Pref (Console.Kernel, File_Pattern), Multiple_Lines);
      New_Text  : String_Access;
      Color     : Gdk_Color;
      Highlight : Gdk_Color;

   begin
      Freeze (Console.Text);

      Highlight := Get_Pref (Console.Kernel, Message_Highlight);

      if Mode = Error then
         Color := Highlight;
      else
         Color := Null_Color;
      end if;

      if Add_LF then
         New_Text := new String'(Text & ASCII.LF);
      else
         New_Text := new String'(Text);
      end if;

      if Highlight_Sloc then
         declare
            Matched   : Match_Array (0 .. 3);
            Start     : Natural := New_Text'First;
            Last      : Natural;
            Real_Last : Natural;

            Line      : Natural := 1;
            Column    : Natural := 1;

         begin
            while Start <= New_Text'Last loop
               Match (File_Location, New_Text (Start .. New_Text'Last),
                      Matched);
               exit when Matched (0) = No_Match;

               Insert
                 (Console.Text,
                  Fore  => Color,
                  Chars => New_Text (Start .. Matched (1).First - 1));

               if Matched (3) = No_Match then
                  Last := Matched (2).Last;
               else
                  Last := Matched (3).Last;
               end if;

               Insert
                 (Console.Text,
                  Fore  => Highlight,
                  Chars => New_Text (Matched (1).First .. Last));

               if Matched (2) /= No_Match then
                  Line := Integer'Value
                    (New_Text (Matched (2).First .. Matched (2).Last));
               end if;

               if Matched (3) /= No_Match then
                  Column := Integer'Value
                    (New_Text (Matched (3).First .. Matched (3).Last));
               end if;


               --  Strip the last ASCII.LF if needed.
               Real_Last := Last;

               while Real_Last < New_Text'Last
                 and then New_Text (Real_Last + 1) /= ASCII.LF
               loop
                  Real_Last := Real_Last + 1;
               end loop;

               Insert
                 (Get_Result_View (Console.Kernel),
                  Location_Identifier,
                  New_Text (Matched (1).First .. Matched (1).Last),
                  Line,
                  Column,
                  New_Text (Last + 1 .. Real_Last));

               Start := Last + 1;
            end loop;

            if Start <= New_Text'Last then
               Insert
                 (Console.Text,
                  Fore  => Color,
                  Chars => New_Text (Start .. New_Text'Last));
            end if;
         end;

      else
         Insert (Console.Text, Fore => Color, Chars => New_Text.all);
      end if;

      Free (New_Text);

      if Mode = Error then
         Trace (Me, Text);
      end if;

      Thaw (Console.Text);

      --  Force a scroll of the text widget. This speeds things up a lot for
      --  programs that output a lot of things, since its takes a very long
      --  time for the text widget to scroll smoothly otherwise (lots of
      --  events...)

      Set_Value (Get_Vadj (Console.Text),
                 Get_Upper (Get_Vadj (Console.Text)) -
                   Get_Page_Size (Get_Vadj (Console.Text)));
   end Insert;

   -----------------------
   -- On_Button_Release --
   -----------------------

   function On_Button_Release
     (Widget : access Gtk_Widget_Record'Class) return Boolean
   is
      Console       : constant Glide_Console := Glide_Console (Widget);
      File_Location : constant Pattern_Matcher :=
        Compile (Get_Pref (Console.Kernel, File_Pattern), Multiple_Lines);
      File_Index    : constant Integer :=
        Integer (Get_Pref (Console.Kernel, File_Pattern_Index));
      Line_Index    : constant Integer :=
        Integer (Get_Pref (Console.Kernel, Line_Pattern_Index));
      Column_Index  : constant Integer :=
        Integer (Get_Pref (Console.Kernel, Column_Pattern_Index));
      Position      : constant Gint := Get_Position (Console.Text);
      Contents      : constant String := Get_Chars (Console.Text, 0);
      Start         : Natural := Natural (Position);
      Last          : Natural := Start;
      Matched       : Match_Array (0 .. 9);
      Line          : Positive;
      Column        : Positive;

   begin
      if Contents'Length = 0
        or else Get_Selection_Start_Pos (Console.Text) /=
                Get_Selection_End_Pos (Console.Text)
      then
         return False;
      end if;

      while Start > Contents'First
        and then Contents (Start - 1) /= ASCII.LF
      loop
         Start := Start - 1;
      end loop;

      while Last < Contents'Last and then Contents (Last + 1) /= ASCII.LF loop
         Last := Last + 1;
      end loop;

      Match (File_Location, Contents (Start .. Last), Matched);

      if Matched (0) /= No_Match then
         Line := Positive'Value
           (Contents (Matched (Line_Index).First ..
                      Matched (Line_Index).Last));

         if Column_Index = 0 or else Matched (Column_Index) = No_Match then
            Column := 1;
         else
            Column := Positive'Value
              (Contents (Matched (Column_Index).First ..
                         Matched (Column_Index).Last));
         end if;

         if Matched (File_Index).First < Matched (File_Index).Last then
            Freeze (Console.Text);
            Select_Region
              (Console.Text, Gint (Start) - 1, Gint (Matched (0).Last));
            Claim_Selection (Console.Text, False, 0);
            Thaw (Console.Text);

            Open_File_Editor
              (Console.Kernel,
               Contents (Matched (File_Index).First ..
                         Matched (File_Index).Last),
               Line, Column, From_Path => True);
         end if;
      end if;

      return False;

   exception
      when others =>
         return False;
   end On_Button_Release;

end Glide_Consoles;
