module Scopes = struct
  let bigquery = "https://www.googleapis.com/auth/bigquery"
end

module Schema = struct
  [@@@warning "-39"]
  type mode = REQUIRED | NULLABLE
  [@@deriving show { with_path = false }]

  let mode_to_yojson mode =
    `String (show_mode mode)

  let mode_of_yojson = function
    | `String "REQUIRED" -> Ok REQUIRED
    | `String "NULLABLE" -> Ok NULLABLE
    | _ -> Error "mode_of_yojson"

  type bq_type =
    | INTEGER
    | NUMERIC
    | STRING
    | DATE
    | TIME
    | TIMESTAMP
  [@@deriving show { with_path = false }]

  let bq_type_to_yojson bq_type =
    `String (show_bq_type bq_type)

  let bq_type_of_yojson = function
    | `String "INTEGER" -> Ok INTEGER
    | `String "NUMERIC" -> Ok NUMERIC
    | `String "STRING" -> Ok STRING
    | `String "DATE" -> Ok DATE
    | `String "TIME" -> Ok TIME
    | `String "TIMESTAMP" -> Ok TIMESTAMP
    | _ -> Error "bq_type_of_yojson"

  type field =
    { name : string
    ; description : string option [@default None]
    ; mode : mode
    ; bq_type : bq_type [@key "type"]
    }
  [@@deriving make, yojson]
  [@@@warning "+39"]
end

module Datasets = struct
  let list () : (string, [> Error.t ]) Lwt_result.t =
    let open Lwt_result.Infix in

    Auth.get_access_token ~scopes:[Scopes.bigquery] ()
    |> Lwt_result.map_err (fun e -> `Gcloud_auth_error e)
    >>= fun token_info ->

    Lwt.catch (fun () ->
        let uri = Uri.make ()
            ~scheme:"https"
            ~host:"www.googleapis.com"
            ~path:(Printf.sprintf "bigquery/v2/projects/%s/datasets" token_info.project_id)
        in
        let headers =
          Cohttp.Header.of_list
            [ "Authorization", Printf.sprintf "Bearer %s" token_info.Auth.token.access_token ]
        in
        Logs_lwt.debug (fun m -> m "GET %a" Uri.pp_hum uri) |> Lwt_result.ok >>= fun () ->
        Cohttp_lwt_unix.Client.get uri ~headers
        |> Lwt_result.ok
      )
      (fun e ->
         (`Network_error e)
         |> Lwt_result.fail)

    >>= fun (resp, body) ->
    match Cohttp.Response.status resp with
    | `OK ->
      Cohttp_lwt.Body.to_string body |> Lwt_result.ok
    | x ->
      Error.of_response_status_code_and_body x body
end

module Jobs = struct
  [@@@warning "-39"]
  type job_reference =
    { jobId : string
    ; projectId : string
    ; location : string
    }
  [@@deriving yojson]

  type query_parameter_type =
    { type_ : Schema.bq_type [@key "type"]
    }
  [@@deriving yojson]

  type query_parameter_value =
    { value : string
    }
  [@@deriving yojson]

  type query_parameter =
    { name : string
    ; parameterType : query_parameter_type
    ; parameterValue : query_parameter_value
    }
  [@@deriving yojson]

  let param ~name ~type_ ~value =
    { name
    ; parameterType = { type_ }
    ; parameterValue = { value }
    }

  type parameter_mode = POSITIONAL | NAMED
  [@@deriving show { with_path = false }]

  let parameter_mode_to_yojson m =
    `String (show_parameter_mode m)

  let parameter_mode_of_yojson = function
    | `String "POSITIONAL" -> Ok POSITIONAL
    | `String "NAMED" -> Ok NAMED
    | _ -> Error "parameter_mode_of_yojson"

  type query_request =
    { kind : string
    ; query : string
    ; useLegacySql : bool
    ; location : string
    ; queryParameters : query_parameter list
    ; parameterMode : parameter_mode option
    }
  [@@deriving yojson]

  type query_response_schema =
    { fields : Schema.field list}
  [@@deriving yojson]

  type query_response_field =
    { v : string }
  [@@deriving yojson]

  type query_response_row =
    { f : query_response_field list}
  [@@deriving yojson]

  type query_response =
    { kind : string
    ; schema : query_response_schema
    ; rows : query_response_row list
    ; pageToken : string option [@default None]
    ; totalRows : string
    ; jobReference : job_reference
    ; jobComplete : bool
    ; totalBytesProcessed : string
    ; cacheHit : bool
    }
  [@@deriving yojson { strict = false }]
  [@@@warning "+39"]

  let query ?project_id ?(use_legacy_sql=false) ?(params = []) q : (query_response, [> Error.t ]) Lwt_result.t =
    let parameter_mode =
      if use_legacy_sql || params = [] then
        None
      else
        Some NAMED
    in

    let request =
      { kind = "bigquery#queryRequest"
      ; query = q
      ; useLegacySql = use_legacy_sql
      ; location = "EU"
      ; parameterMode = parameter_mode
      ; queryParameters = params
      }
    in

    let open Lwt_result.Infix in

    Auth.get_access_token ~scopes:[Scopes.bigquery] ()
    |> Lwt_result.map_err (fun e -> `Gcloud_auth_error e)
    >>= fun token_info ->

    let project_id = project_id |> CCOpt.get_or ~default:token_info.project_id in

    Lwt.catch (fun () ->
        let uri = Uri.make ()
            ~scheme:"https"
            ~host:"www.googleapis.com"
            ~path:(Printf.sprintf "bigquery/v2/projects/%s/queries" project_id)
        in
        let headers =
          Cohttp.Header.of_list
            [ ( "Authorization", Printf.sprintf "Bearer %s" token_info.Auth.token.access_token )
            ; ( "Content-Type", "application/json" )
            ]
        in
        let body_str =
          request
          |> query_request_to_yojson
          |> Yojson.Safe.to_string
        in
        let body =
          body_str
          |> Cohttp_lwt.Body.of_string
        in
        Logs_lwt.debug (fun m -> m "POST %a with %S [%a]" Uri.pp_hum uri body_str Cohttp.Header.pp_hum headers) |> Lwt_result.ok >>= fun () ->
        Cohttp_lwt_unix.Client.post uri ~headers ~body
        |> Lwt_result.ok
      )
      (fun e ->
         (`Network_error e)
         |> Lwt_result.fail)

    >>= fun (resp, body) ->
    match Cohttp.Response.status resp with
    | `OK ->
      Cohttp_lwt.Body.to_string body |> Lwt_result.ok >>= fun body_str ->
      Logs_lwt.debug (fun m -> m "%s" body_str) |> Lwt_result.ok >>= fun () ->
      body_str
      |> Yojson.Safe.from_string
      |> query_response_of_yojson
      |> CCResult.map_err (fun msg -> `Json_transform_error msg)
      |> Lwt.return
    | status_code ->
      Error.of_response_status_code_and_body status_code body
end
