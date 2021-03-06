(*
 * Copyright (c) 2018 - present Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *)
open! IStd
module L = Logging

let get_all () =
  let db = ResultsDatabase.get_database () in
  Sqlite3.prepare db "SELECT source_file FROM source_files"
  |> SqliteUtils.sqlite_result_rev_list_step db ~log:"getting all source files"
  |> List.filter_map ~f:(Option.map ~f:SourceFile.SQLite.deserialize)


let load_proc_names_statement =
  ResultsDatabase.register_statement
    "SELECT procedure_names FROM source_files WHERE source_file = :k"


let proc_names_of_source source =
  ResultsDatabase.with_registered_statement load_proc_names_statement ~f:(fun db load_stmt ->
      SourceFile.SQLite.serialize source |> Sqlite3.bind load_stmt 1
      |> SqliteUtils.check_sqlite_error db ~log:"load bind source file" ;
      SqliteUtils.sqlite_result_step ~finalize:false db ~log:"SourceFiles.proc_names_of_source"
        load_stmt
      |> Option.value_map ~default:[] ~f:Typ.Procname.SQLiteList.deserialize )


let exists_source_statement =
  ResultsDatabase.register_statement "SELECT 1 FROM source_files WHERE source_file = :k"


let is_captured source =
  ResultsDatabase.with_registered_statement exists_source_statement ~f:(fun db exists_stmt ->
      SourceFile.SQLite.serialize source |> Sqlite3.bind exists_stmt 1
      (* :k *)
      |> SqliteUtils.check_sqlite_error db ~log:"load captured source file" ;
      SqliteUtils.sqlite_result_step ~finalize:false ~log:"SourceFiles.is_captured" db exists_stmt
      |> Option.is_some )


let is_non_empty_statement =
  ResultsDatabase.register_statement "SELECT 1 FROM source_files LIMIT 1"


let is_empty () =
  ResultsDatabase.with_registered_statement is_non_empty_statement ~f:(fun db stmt ->
      SqliteUtils.sqlite_result_step ~finalize:false ~log:"SourceFiles.is_empty" db stmt
      |> Option.is_none )


let is_freshly_captured_statement =
  ResultsDatabase.register_statement
    "SELECT freshly_captured FROM source_files WHERE source_file = :k"


let is_freshly_captured source =
  ResultsDatabase.with_registered_statement is_freshly_captured_statement ~f:(fun db load_stmt ->
      SourceFile.SQLite.serialize source |> Sqlite3.bind load_stmt 1
      |> SqliteUtils.check_sqlite_error db ~log:"load bind source file" ;
      SqliteUtils.sqlite_result_step ~finalize:false ~log:"SourceFiles.is_freshly_captured" db
        load_stmt
      |> Option.value_map ~default:false ~f:(function [@warning "-8"] Sqlite3.Data.INT p ->
             Int64.equal p Int64.one ) )


let mark_all_stale_statement =
  ResultsDatabase.register_statement "UPDATE source_files SET freshly_captured = 0"


let mark_all_stale () =
  ResultsDatabase.with_registered_statement mark_all_stale_statement ~f:(fun db stmt ->
      SqliteUtils.sqlite_unit_step db ~finalize:false ~log:"mark_all_stale" stmt )
