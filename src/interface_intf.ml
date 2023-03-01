open Base

module type Pre_partial = sig
  type 'a t [@@deriving sexp_of]

  val iter : 'a t -> f:('a -> unit) -> unit
  val iter2 : 'a t -> 'b t -> f:('a -> 'b -> unit) -> unit
  val map : 'a t -> f:('a -> 'b) -> 'b t
  val map2 : 'a t -> 'b t -> f:('a -> 'b -> 'c) -> 'c t
  val to_list : 'a t -> 'a list
end

module type Pre = sig
  include Pre_partial

  val t : (string * int) t
end

module type Ast = sig
  (** The PPX can optionally generate an [ast] field containing an [Ast.t]. This
      represents the structure of the interface, including how it is constructed from
      fields, arrays, lists and sub-modules.

      This is of particular use when generating further code from the interface i.e. a
      register interace specification.

      [ast]s are not generated by default. *)
  module rec Ast : sig
    type t = Field.t list [@@deriving sexp_of]
  end

  and Field : sig
    type t =
      { name : string (** Name of the field *)
      ; type_ : Type.t (** Field type - a signal or a sub-module *)
      ; sequence : Sequence.t option (** Is the field type an array or list? *)
      ; doc : string option
      (** Ocaml documentation string, if any. Note that this must be placed in the [ml]
          and not [mli].*)
      }
    [@@deriving sexp_of]
  end

  and Type : sig
    type t =
      | Signal of
          { bits : int
          ; rtlname : string
          }
      | Module of
          { name : string
          ; ast : Ast.t
          }
    [@@deriving sexp_of]
  end

  and Sequence : sig
    module Kind : sig
      type t =
        | Array
        | List
      [@@deriving sexp_of]
    end

    type t =
      { kind : Kind.t
      ; length : int
      }
    [@@deriving sexp_of]
  end

  type t = Ast.t [@@deriving sexp_of]
end

(** Monomorphic combinatorial operations on Hardcaml interfaces. *)
module type Comb_monomorphic = sig
  type comb
  type t [@@deriving sexp_of]

  (** Raise if the widths of [t] do not match those specified in the interface. *)
  val assert_widths : t -> unit

  (** Each field is set to the constant integer value provided. *)
  val of_int : int -> t

  val const : int -> t [@@deprecated "[since 2019-11] interface const"]

  (** Pack interface into a vector. *)
  val pack : ?rev:bool -> t -> comb

  (** Unpack interface from a vector. *)
  val unpack : ?rev:bool -> comb -> t

  (** Multiplex a list of interfaces. *)
  val mux : comb -> t list -> t

  val mux2 : comb -> t -> t -> t

  (** Concatenate a list of interfaces. *)
  val concat : t list -> t

  val priority_select
    : ((comb, t) Comb.with_valid2 list -> (comb, t) Comb.with_valid2)
        Comb.optional_branching_factor

  val priority_select_with_default
    : ((comb, t) Comb.with_valid2 list -> default:t -> t) Comb.optional_branching_factor

  val onehot_select
    : ((comb, t) Comb.with_valid2 list -> t) Comb.optional_branching_factor
end

module type Comb = sig
  type 'a interface
  type comb
  type t = comb interface [@@deriving sexp_of]

  include Comb_monomorphic with type t := comb interface and type comb := comb

  (** Actual bit widths of each field. *)
  val widths : t -> int interface

  (** [consts c] sets each field to the integer value in [c] using the declared field bit
      width. *)
  val of_ints : int interface -> t

  val consts : int interface -> t [@@deprecated "[since 2019-11] interface consts"]
end

module type Names_and_widths = sig
  val t : (string * int) list

  type tag

  val port_names : string list
  val port_widths : int list
  val tags : tag list
end

module type Of_signal_functions = sig
  type t

  (** Create a wire for each field.  If [named] is true then wires are given the RTL field
      name.  If [from] is provided the wire is attached to each given field in [from]. *)
  val wires
    :  ?named:bool (** default is [false]. *)
    -> ?from:t (** No default *)
    -> unit
    -> t

  (** Defines a register over values in this interface. [enable] defaults to vdd. *)
  val reg : ?enable:Signal.t -> Reg_spec.t -> t -> t

  (** Defines a register pipeline over values in this interface. [enable]
      defaults to vdd and [attributes] defaults to an empty list. *)
  val pipeline
    :  ?attributes:Rtl_attribute.t list
    -> ?enable:Signal.t
    -> n:int
    -> Reg_spec.t
    -> t
    -> t

  val assign : t -> t -> unit
  val ( <== ) : t -> t -> unit

  (** [inputs t] is [wires () ~named:true]. *)
  val inputs : unit -> t

  (** [outputs t] is [wires () ~from:t ~named:true]. *)
  val outputs : t -> t

  (** Apply name to field of the interface. Add [prefix] and [suffix] if specified. *)
  val apply_names
    :  ?prefix:string (** Default is [""] *)
    -> ?suffix:string (** Default is [""] *)
    -> ?naming_op:(Signal.t -> string -> Signal.t) (** Default is [Signal.(--)] *)
    -> t
    -> t

  (** Checks the port widths of the signals in the interface. Raises if they mismatch. *)
  val validate : t -> unit
end

module type S = sig
  include Pre
  include Equal.S1 with type 'a t := 'a t

  (** RTL names specified in the interface definition - commonly also the OCaml field
      name. *)
  val port_names : string t

  (** Bit widths specified in the interface definition. *)
  val port_widths : int t

  type tag

  val tags : tag t

  (** Create association list indexed by tag. *)
  val to_alist : 'a t -> (tag * 'a) list

  (** Create interface from association list indexed by tag. *)
  val of_alist : (tag * 'a) list -> 'a t

  (** Sum of all port widths specified in the interface definition. *)
  val sum_of_port_widths : int

  module Unsafe_assoc_by_port_name : sig
    (** Create association list indexed by field names. *)
    val to_alist : 'a t -> (string * 'a) list

    (** Create interface from association list indexed by field names. *)
    val of_alist : (string * 'a) list -> 'a t
  end

  val zip : 'a t -> 'b t -> ('a * 'b) t
  val zip3 : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
  val zip4 : 'a t -> 'b t -> 'c t -> 'd t -> ('a * 'b * 'c * 'd) t
  val zip5 : 'a t -> 'b t -> 'c t -> 'd t -> 'e t -> ('a * 'b * 'c * 'd * 'e) t
  val map3 : 'a t -> 'b t -> 'c t -> f:('a -> 'b -> 'c -> 'd) -> 'd t
  val map4 : 'a t -> 'b t -> 'c t -> 'd t -> f:('a -> 'b -> 'c -> 'd -> 'e) -> 'e t

  val map5
    :  'a t
    -> 'b t
    -> 'c t
    -> 'd t
    -> 'e t
    -> f:('a -> 'b -> 'c -> 'd -> 'e -> 'f)
    -> 'f t

  val iter3 : 'a t -> 'b t -> 'c t -> f:('a -> 'b -> 'c -> unit) -> unit
  val iter4 : 'a t -> 'b t -> 'c t -> 'd t -> f:('a -> 'b -> 'c -> 'd -> unit) -> unit

  val iter5
    :  'a t
    -> 'b t
    -> 'c t
    -> 'd t
    -> 'e t
    -> f:('a -> 'b -> 'c -> 'd -> 'e -> unit)
    -> unit

  val fold : 'a t -> init:'acc -> f:('acc -> 'a -> 'acc) -> 'acc
  val fold2 : 'a t -> 'b t -> init:'acc -> f:('acc -> 'a -> 'b -> 'acc) -> 'acc
  val scan : 'a t -> init:'acc -> f:('acc -> 'a -> 'acc * 'b) -> 'b t
  val scan2 : 'a t -> 'b t -> init:'acc -> f:('acc -> 'a -> 'b -> 'acc * 'c) -> 'c t

  (** Offset of each field within the interface.  The first field is placed at the least
      significant bit, unless the [rev] argument is true. *)
  val offsets : ?rev:bool (** default is [false]. *) -> unit -> int t

  (** Take a list of interfaces and produce a single interface where each field is a
      list. *)
  val of_interface_list : 'a t list -> 'a list t

  (** Create a list of interfaces from a single interface where each field is a list.
      Raises if all lists don't have the same length. *)
  val to_interface_list : 'a list t -> 'a t list

  (** Similar to [Monad.all] for lists -- combine and lift the monads to outside the
      interface.
  *)
  module All (M : Monad.S) : sig
    val all : 'a M.t t -> 'a t M.t
  end

  (** Equivalent to All(Or_error).all. This is made a special case for convenience. *)
  val or_error_all : 'a Or_error.t t -> 'a t Or_error.t

  module type Comb = Comb with type 'a interface := 'a t

  module Make_comb (Comb : Comb.S) : Comb with type comb = Comb.t
  module Of_bits : Comb with type comb = Bits.t

  module Of_signal : sig
    include Comb with type comb = Signal.t
    include Of_signal_functions with type t := t
  end

  (** Helper functions to ease usage of the Always API when working with interfaces. *)
  module Of_always : sig
    val value : Always.Variable.t t -> Signal.t t

    (** Assign a interface containing variables in an always block. *)
    val assign : Always.Variable.t t -> Signal.t t -> Always.t

    (** Creates a interface container with register variables. *)
    val reg : ?enable:Signal.t -> Reg_spec.t -> Always.Variable.t t

    (** Creates a interface container with wire variables, e.g. [Foo.Of_always.wire
        Signal.zero], which would yield wires defaulting to zero. *)
    val wire : (int -> Signal.t) -> Always.Variable.t t

    (** Apply names to field of the interface. Add [prefix] and [suffix] if specified. *)
    val apply_names
      :  ?prefix:string (** Default is [""] *)
      -> ?suffix:string (** Default is [""] *)
      -> ?naming_op:(Signal.t -> string -> Signal.t) (** Default is [Signal.(--)] *)
      -> Always.Variable.t t
      -> unit
  end

  module Names_and_widths : Names_and_widths with type tag := tag
end

(** Monomorphic functions on Hardcaml interfaces. Note that a functor (or a function)
    accepting a argument on this monomorphic module type will type check successfully
    against [S] above, since [S] more general than the monomorphic type below.
*)
module type S_monomorphic = sig
  type a
  type t
  type tag

  val iter : t -> f:(a -> unit) -> unit
  val iter2 : t -> t -> f:(a -> a -> unit) -> unit
  val map : t -> f:(a -> a) -> t
  val map2 : t -> t -> f:(a -> a -> a) -> t
  val to_list : t -> a list
  val to_alist : t -> (tag * a) list
  val of_alist : (tag * a) list -> t

  module Unsafe_assoc_by_port_name : sig
    val to_alist : t -> (string * a) list
    val of_alist : (string * a) list -> t
  end

  val map3 : t -> t -> t -> f:(a -> a -> a -> a) -> t
  val map4 : t -> t -> t -> t -> f:(a -> a -> a -> a -> a) -> t
  val map5 : t -> t -> t -> t -> t -> f:(a -> a -> a -> a -> a -> a) -> t
  val iter3 : t -> t -> t -> f:(a -> a -> a -> unit) -> unit
  val iter4 : t -> t -> t -> t -> f:(a -> a -> a -> a -> unit) -> unit
  val iter5 : t -> t -> t -> t -> t -> f:(a -> a -> a -> a -> a -> unit) -> unit
  val fold : t -> init:'acc -> f:('acc -> a -> 'acc) -> 'acc
  val fold2 : t -> t -> init:'acc -> f:('acc -> a -> a -> 'acc) -> 'acc

  module Names_and_widths : Names_and_widths with type tag := tag
end

module type S_Of_signal = sig
  module Of_signal : sig
    include Comb_monomorphic with type comb := Signal.t
    include Of_signal_functions with type t := t
  end

  include S_monomorphic with type t := Of_signal.t and type a := Signal.t
end

module type Empty = sig
  type 'a t = None

  include S with type 'a t := 'a t
end

module type Interface = sig
  module type Pre_partial = Pre_partial
  module type Pre = Pre
  module type S = S
  module type S_Of_signal = S_Of_signal
  module type Ast = Ast
  module type Empty = Empty

  module Ast : Ast
  module Empty : Empty

  module type S_with_ast = sig
    include S

    val ast : Ast.t
  end

  (** Type of functions representing the implementation of a circuit from an input to
      output interface. *)
  module Create_fn (I : S) (O : S) : sig
    type 'a t = 'a I.t -> 'a O.t [@@deriving sexp_of]
  end

  module Make (X : Pre) : S with type 'a t := 'a X.t

  (** An interface for a single value *)
  module Value (S : sig
      val port_name : string
      val port_width : int
    end) : S with type 'a t = 'a

  (** Recreate a Hardcaml Interface with the same type, but different port names / widths. *)
  module Update
      (Pre : Pre) (M : sig
                     val t : (string * int) Pre.t
                   end) : S with type 'a t = 'a Pre.t

  (** Creates a new hardcaml interface by converting between functions. This can
      be used to implement Hardcaml.Interface.S on types that otherwise can't
      use [@@deriving hardcaml]
  *)
  module Make_interface_with_conversion
      (Repr : S) (M : sig
                    type 'a t [@@deriving sexp_of]

                    val t_of_repr : 'a Repr.t -> 'a t
                    val repr_of_t : 'a t -> 'a Repr.t
                  end) : S with type 'a t = 'a M.t
end
