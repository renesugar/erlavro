%%%-------------------------------------------------------------------
%%% @doc General Avro handling code.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(avro).

-export([is_named_type/1]).
-export([get_type_name/1]).
-export([get_type_namespace/1]).
-export([get_type_fullname/1]).

-export([split_type_name/2]).
-export([split_type_name/3]).
-export([build_type_fullname/2]).
-export([build_type_fullname/3]).

-export([verify_type/1]).

-include("erlavro.hrl").

%%%===================================================================
%%% API: Accessing types' properties
%%%===================================================================

%% Returns true if the type can have its own name defined in schema.
-spec is_named_type(avro_type()) -> boolean().

is_named_type(#avro_record_type{}) -> true;
is_named_type(#avro_enum_type{})   -> true;
is_named_type(#avro_fixed_type{})  -> true;
is_named_type(_)                   -> false.

%% Returns the type's name. If the type is named then content of
%% its name field is returned which can be short name or full name,
%% depending on how the type was specified. If the type is unnamed
%% then Avro name of the type is returned.
-spec get_type_name(avro_type()) -> string().

get_type_name(#avro_primitive_type{name = Name}) -> Name;
get_type_name(#avro_record_type{name = Name})    -> Name;
get_type_name(#avro_enum_type{name = Name})      -> Name;
get_type_name(#avro_array_type{})                -> ?AVRO_ARRAY;
get_type_name(#avro_map_type{})                  -> ?AVRO_MAP;
get_type_name(#avro_union_type{})                -> ?AVRO_UNION;
get_type_name(#avro_fixed_type{name = Name})     -> Name.

%% Returns the type's namespace exactly as it is set in the type.
%% Depending on how the type was specified it could the namespace
%% or just an empty string if the name contains namespace in it.
%% If the type can't have namespace then empty string is returned.
-spec get_type_namespace(avro_type()) -> string().

get_type_namespace(#avro_primitive_type{})            -> "";
get_type_namespace(#avro_record_type{namespace = Ns}) -> Ns;
get_type_namespace(#avro_enum_type{namespace = Ns})   -> Ns;
get_type_namespace(#avro_array_type{})                -> "";
get_type_namespace(#avro_map_type{})                  -> "";
get_type_namespace(#avro_union_type{})                -> "";
get_type_namespace(#avro_fixed_type{namespace = Ns})  -> Ns.

%% Returns fullname stored inside the type. For unnamed types
%% their Avro name is returned.
-spec get_type_fullname(avro_type()) -> string().

get_type_fullname(#avro_primitive_type{name = Name})  -> Name;
get_type_fullname(#avro_record_type{fullname = Name}) -> Name;
get_type_fullname(#avro_enum_type{fullname = Name})   -> Name;
get_type_fullname(#avro_array_type{})                 -> ?AVRO_ARRAY;
get_type_fullname(#avro_map_type{})                   -> ?AVRO_MAP;
get_type_fullname(#avro_union_type{})                 -> ?AVRO_UNION;
get_type_fullname(#avro_fixed_type{fullname = Name})  -> Name.

%%%===================================================================
%%% API: Calculating of canonical short and full names of types
%%%===================================================================

%% Splits type's name parts to its canonical short name and namespace.
-spec split_type_name(string(), string(), string()) -> {string(), string()}.

split_type_name(TypeName, Namespace, EnclosingNamespace) ->
  case split_fullname(TypeName) of
    {_, _} = N ->
      %% TypeName contains name and namespace
      N;
    false ->
      %% TypeName is a name without namespace, choose proper namespace
      ProperNs = if Namespace =:= "" -> EnclosingNamespace;
                    true             -> Namespace
                 end,
      {TypeName, ProperNs}
  end.

%% Same thing as before, but uses name and namespace from the specified type.
-spec split_type_name(avro_type(), string()) -> {string(), string()}.

split_type_name(Type, EnclosingNamespace) ->
  split_type_name(get_type_name(Type),
                  get_type_namespace(Type),
                  EnclosingNamespace).

%% Constructs the type's full name from provided name and namespace
-spec build_type_fullname(string(), string(), string()) -> string().

build_type_fullname(TypeName, Namespace, EnclosingNamespace) ->
  {ShortName, ProperNs} =
    split_type_name(TypeName, Namespace, EnclosingNamespace),
  make_fullname(ShortName, ProperNs).

%% Same thing as before but uses name and namespace from the specified type.
-spec build_type_fullname(avro_type(), string()) -> string().

build_type_fullname(Type, EnclosingNamespace) ->
  build_type_fullname(get_type_name(Type),
                      get_type_namespace(Type),
                      EnclosingNamespace).

%%%===================================================================
%%% API: Checking correctness of names and types specifications
%%%===================================================================

%% Check correctness of the name portion of type names, record field names and
%% enums symbols (everything where dots should not present in).
-spec is_correct_name(string()) -> boolean().

is_correct_name([])    -> false;
is_correct_name([H])   -> is_correct_first_symbol(H);
is_correct_name([H|T]) -> is_correct_first_symbol(H) andalso
                          is_correct_name_tail(T).

%% Check correctness of type name or namespace (where name parts can be splitted
%% with dots).
-spec is_correct_dotted_name(string()) -> boolean().

is_correct_dotted_name(Name) ->
  case split_fullname(Name) of
    false       -> is_correct_name(Name);
    {SName, Ns} -> is_correct_name(SName) andalso
                   is_correct_dotted_name(Ns)
  end.

%% Verify overall type definition for correctness. Error is thrown
%% when issues are found.
-spec verify_type(avro_type()) -> ok.

verify_type(Type) ->
    case is_named_type(Type) of
        true  -> verify_type_name(Type);
        false -> ok
    end.

%% Assign the Value to a "variable" of type Type.
%% Type can be a valid Avro type or name of a type.
%% Value can be any Avro value or just erlang term,
%% the function will try to convert the term to an Avro value
%% in the last case.

%% 1. name <- avro_value  : type_name(avro_value) =:= name
%% 2. name <- erlang_term : impossible
%% 3. type <- avro_value  : type_name(avro_value) =:= type_name(type)
%% 4. type <- erlang_term : type_module:from_value(erlang_term)


%% get_type_module(#avro_primitive_type{}) -> avro_primitive;
%% get_type_module(#avro_record_type{})    -> avro_record;
%% get_type_module(#avro_enum_type{})      -> avro_enum;
%% get_type_module(#avro_array_type{})     -> avro_array;
%% get_type_module(#avro_map_type{})       -> avro_map;
%% get_type_module(#avro_union_type{})     -> avro_union;
%% get_type_module(#avro_fixed_type{})     -> avro_fixed;
%% get_type_module(_)                      -> undefined.

%%%===================================================================
%%% Internal functions
%%%===================================================================

reserved_type_names() ->
    [?AVRO_NULL, ?AVRO_BOOLEAN, ?AVRO_INT, ?AVRO_LONG, ?AVRO_FLOAT,
     ?AVRO_DOUBLE, ?AVRO_BYTES, ?AVRO_STRING, ?AVRO_ARRAY, ?AVRO_MAP,
     ?AVRO_UNION].

is_correct_first_symbol(S) -> (S >= $A andalso S =< $Z) orelse
                              (S >= $a andalso S =< $z) orelse
                              S =:= $_.

is_correct_symbol(S) -> is_correct_first_symbol(S) orelse
                        (S >= $0 andalso S =< $9).

is_correct_name_tail([])    -> true;
is_correct_name_tail([H|T]) -> is_correct_symbol(H) andalso
                               is_correct_name_tail(T).

verify_type_name(Type) ->
    Name = get_type_name(Type),
    Ns = get_type_namespace(Type),
    Fullname = get_type_fullname(Type),
    error_if_false(is_correct_dotted_name(Name),
                   {invalid_name, Name}),
    error_if_false(Ns =:= "" orelse is_correct_dotted_name(Ns),
                   {invalid_name, Ns}),
    error_if_false(is_correct_dotted_name(Fullname),
                   {invalid_name, Fullname}),
    %% It is important to call canonicalize_name after basic checks,
    %% because it assumes that all names are correct.
    %% We are not interested in the namespace here, so we can ignore
    %% EnclosingExtension value.
    {CanonicalName, _} = split_type_name(Name, Ns, ""),
    error_if_false(not lists:member(CanonicalName, reserved_type_names()),
                   reserved_name_is_used_for_type_name).

%% Splits FullName to {Name, Namespace} or returns false
%% if FullName is not a full name.
%% The function can fail if it is called on badly formatted names.
-spec split_fullname(string()) -> {string(), string()} | false.
split_fullname(FullName) ->
    case string:rchr(FullName, $.) of
        0 ->
            %% Dot not found
            false;
        DotPos ->
            { string:substr(FullName, DotPos + 1)
            , string:substr(FullName, 1, DotPos-1)
            }
    end.

make_fullname(Name, "") ->
  Name;
make_fullname(Name, Namespace) ->
  Namespace ++ "." ++ Name.

error_if_false(true, _Err) -> ok;
error_if_false(false, Err) -> erlang:error(Err).

%%%===================================================================
%%% Tests
%%%===================================================================

-include_lib("eunit/include/eunit.hrl").

-ifdef(EUNIT).

get_test_type(Name, Namespace) ->
  #avro_fixed_type{name = Name,
                   namespace = Namespace,
                   size = 16,
                   fullname = build_type_fullname(Name, Namespace, "")}.

is_correct_name_test() ->
  CorrectNames = ["_", "a", "Aa1", "a_A"],
  IncorrectNames = ["", "1", " a", "a ", " a ", ".", "a.b.c"],
  [?assert(is_correct_name(Name)) || Name <- CorrectNames],
  [?assertNot(is_correct_name(Name)) || Name <- IncorrectNames].

is_correct_dotted_name_test() ->
  CorrectNames = ["_", "a", "A._1", "a1.b2.c3"],
  IncorrectNames = ["", "1", " a.b.c", "a.b.c ", " a.b.c ", "a..b", ".a.b",
                    "a.1.b", "!", "-", "a. b.c"],
  [?assert(is_correct_dotted_name(Name)) || Name <- CorrectNames],
  [?assertNot(is_correct_dotted_name(Name)) || Name <- IncorrectNames].

verify_type_test() ->
  ?assertEqual(ok, verify_type(get_test_type("tname", "name.space"))),
  ?assertError({invalid_name, _}, verify_type(get_test_type("", ""))),
  ?assertError({invalid_name, _}, verify_type(get_test_type("", "name.space"))),
  ?assertEqual(ok, verify_type(get_test_type("tname", ""))).

split_type_name_test() ->
  ?assertEqual({"tname", ""},
               split_type_name("tname", "", "")),
  ?assertEqual({"tname", "name.space"},
               split_type_name("tname", "name.space", "enc.losing")),
  ?assertEqual({"tname", "name.space"},
               split_type_name("name.space.tname", "", "name1.space1")),
  ?assertEqual({"tname", "enc.losing"},
               split_type_name("tname", "", "enc.losing")).

get_type_fullname_test() ->
  ?assertEqual("name.space.tname",
               get_type_fullname(get_test_type("tname", "name.space"))),
  ?assertEqual("int",
               get_type_fullname(avro_primitive:int_type())).

-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
