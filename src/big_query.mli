module Scopes : sig
  val bigquery : string
end

module Schema : sig
  type mode = REQUIRED | NULLABLE | REPEATED
  val show_mode : mode -> string

  type bq_type =
    | BOOL
    | INTEGER
    | NUMERIC
    | FLOAT
    | STRING
    | DATE
    | TIME
    | TIMESTAMP
    | RECORD
  val show_bq_type : bq_type -> string

  type field
  val make_field : name:string -> ?description:string option -> mode:mode -> bq_type:bq_type -> ?fields:field list -> unit -> field
  val field_to_yojson : field -> Yojson.Safe.json
  val bq_type_of_field : field -> bq_type
  val name_of_field : field -> string
  val mode_of_field : field -> mode
end

module Datasets : sig
  val get : ?project_id:string -> dataset_id:string -> unit -> (string, [> Error.t ]) Lwt_result.t
  val list : ?project_id:string -> unit -> (string, [> Error.t ]) Lwt_result.t

  module Tables : sig

    type table =
      { id : string;
        kind: string;
        friendlyName: string option;
        expirationTime : string option;
        creationTime : string }

    type resp =
      { tables : table list;
        kind: string;
        etag: string;
        nextPageToken: string option;
        totalItems : int }

    val list : ?project_id:string ->  ?max_results:int -> ?page_token:string -> dataset_id:string -> unit -> (resp, [> Error.t ]) Lwt_result.t
  end

end

module Jobs : sig
  module Param : sig
    type numeric
    type date
    type time
    type timestamp
    type 'a param'

    val bool : bool -> bool param'
    val integer : int -> int param'
    val numeric : string -> numeric param'
    val string : string -> string param'
    val date : string -> date param'
    val time : string -> time param'
    val timestamp : string -> timestamp param'
    val array : ('a -> 'b param') -> 'a list -> 'b param'

    type 'a struct_param
    val struct_ : 'a struct_param -> 'a param'
    val empty_struct : unit struct_param
    val with_field : name:string -> 'a param' -> 'b struct_param -> ('a * 'b) struct_param

    type query_parameter

    val make : name:string -> 'a param' -> query_parameter
  end

  type job_reference =
    { job_id : string
    ; project_id : string
    ; location : string
    }

  type query_response_schema =
    { fields : Schema.field list}

  type query_response_field =
    { v : query_response_value }
  and query_response_value =
    | Null
    | String of string
    | List of query_response_field list

  type query_response_row =
    { f : query_response_field list}

  type query_response_data =
    { schema : query_response_schema
    ; rows : query_response_row list
    ; page_token : string option
    ; total_rows : string option
    ; num_dml_affected_rows : string option
    ; total_bytes_processed : string
    ; cache_hit : bool
    }

  (** Type of query responses. We may or may not have the data, depending on
      whether the job completed within the timeout.

      Tip: use {!poll_until_complete} to poll the job until we have some concrete data.
  *)
  type query_response =
    { kind : string
    ; job_reference : job_reference
    ; job_complete : query_response_data option
    }

  val query_response_to_yojson : query_response -> Yojson.Safe.json

  val query : ?project_id:string -> ?use_legacy_sql:bool -> ?params:Param.query_parameter list -> ?location:string -> string -> (query_response, [> Error.t ]) Lwt_result.t
  val get_query_results : ?page_token:string -> job_reference -> (query_response, [> Error.t ]) Lwt_result.t

  (** Type of query responses, when the job is complete and we definitely have some data. *)
  type query_response_complete =
    { kind : string
    ; job_reference : job_reference
    ; data : query_response_data
    }
  val query_response_complete_to_yojson : query_response_complete -> Yojson.Safe.json

  val poll_until_complete : ?attempts:int -> query_response -> (query_response_complete, [> Error.t ]) result Lwt.t

  val single_row : (query_response_row -> ('a, string) result) -> query_response_data -> ('a, string) result
  val many_rows : (query_response_row -> ('a, string) result) -> query_response_data -> ('a list, string) result
  val single_field : (query_response_field -> ('a, string) result) -> query_response_row -> ('a, string) result
  val string : query_response_field -> (string, string) result
  val int : query_response_field -> (int, string) result
  val bool : query_response_field -> (bool, string) result
  val float : query_response_field -> (float, string) result
  val nullable : (query_response_field -> ('a, string) result) -> query_response_field -> ('a option, string) result
  val list : (query_response_field -> ('a, string) result) -> query_response_field -> ('a list, string) result
  val tag : string -> ('a, string) result -> ('a, string) result
end
