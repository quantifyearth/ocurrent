(* Static analysis of a build pipeline. *)

type t

(* The [~bind] argument is the static node of the bind operator whose callback
   created the object, if any. *)

val return   : bind:t option -> unit -> t
val fail     : bind:t option -> unit -> t
val pending  : bind:t option -> unit -> t
val pair     : bind:t option -> t -> t -> t
val bind     : bind:t option -> name:string -> t -> t
val list_map : bind:t option -> f:t -> t -> t
val gate     : bind:t option -> on:t -> t -> t

val pp : t Fmt.t
val pp_dot : t Fmt.t
