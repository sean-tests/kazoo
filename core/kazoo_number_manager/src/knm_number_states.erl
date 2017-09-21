%%%-------------------------------------------------------------------
%%% @copyright (C) 2016-2017, 2600Hz INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   Peter Defebvre
%%%   Pierre Fenoll
%%%-------------------------------------------------------------------
-module(knm_number_states).

-export([to_options_state/1]).

-include("knm.hrl").

-type kn() :: knm_number:knm_number().

-define(TO_STATE2(ToStateF, T0)
       ,knm_numbers:merge_okkos(
          [begin
               NewT0 = knm_numbers:set_oks(Ns, knm_numbers:set_todo(T0, [])),
               knm_numbers:do(fun (T) -> ToStateF(T, State) end, NewT0)
           end
           || {State, Ns} <- group_by_state(T0),
              [] =/= Ns
          ])).

-spec to_options_state(knm_numbers:collection()) -> knm_numbers:collection().
to_options_state(T) ->
    Options = knm_numbers:options(T),
    TargetState = knm_number_options:state(Options),
    ?LOG_DEBUG("attempting to change to state ~s", [TargetState]),
    change_state(T, TargetState).

-spec change_state(knm_numbers:collection(), ne_binary()) -> knm_numbers:collection().
change_state(T, ?NUMBER_STATE_RESERVED) ->
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_RESERVED) end
                     ,fun to_reserved/1
                     ]);
change_state(T, ?NUMBER_STATE_IN_SERVICE) ->
    to_in_service(T);
change_state(T, ?NUMBER_STATE_AVAILABLE) ->
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_AVAILABLE) end
                     ,fun to_available/1
                     ]);
change_state(T, ?NUMBER_STATE_AGING) ->
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_AGING) end
                     ,fun to_aging/1
                     ]);
change_state(T, ?NUMBER_STATE_PORT_IN) ->
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_PORT_IN) end
                     ,fun to_port_in/1
                     ]);
change_state(T, _State) ->
    Ns = knm_numbes:todo(T),
    lager:debug("unhandled state change to ~p", [_State]),
    Error = knm_errors:to_json('invalid_state'),
    knm_numbers:ko(Ns, Error, T).

-spec to_port_in(knm_numbers:collection()) -> knm_numbers:collection().
to_port_in(T0) -> ?TO_STATE2(to_port_in, T0).

to_port_in(T, ?NUMBER_STATE_PORT_IN) ->
    knm_numbers:pipe(T
                    ,[fun move_to_port_in_state/1
                     ]);
to_port_in(T, State) ->
    invalid_state_transition(T, State, ?NUMBER_STATE_PORT_IN).

-spec to_aging(knm_numbers:collection()) -> knm_numbers:collection().
to_aging(T0) -> ?TO_STATE2(to_aging, T0).

to_aging(T, ?NUMBER_STATE_AGING) ->
    knm_numbers:pipe(T
                    ,[fun move_to_aging_state/1
                     ]);
to_aging(T, ?NUMBER_STATE_RELEASED) ->
    knm_numbers:pipe(T
                    ,[fun move_to_aging_state/1
                     ]);
to_aging(T, ?NUMBER_STATE_AVAILABLE) ->
    knm_numbers:pipe(T
                    ,[fun move_to_aging_state/1
                     ]);
to_aging(T, State) ->
    invalid_state_transition(T, State, ?NUMBER_STATE_AGING).

-spec to_available(knm_numbers:collection()) -> knm_numbers:collection().
to_available(T0) -> ?TO_STATE2(to_available, T0).

to_available(T, ?NUMBER_STATE_AVAILABLE) ->
    knm_numbers:pipe(T
                    ,[fun authorize/1
                     ,fun move_to_available_state/1
                     ,fun knm_services:activate_phone_number/1
                     ]);
to_available(T, State) ->
    invalid_state_transition(T, State, ?NUMBER_STATE_AVAILABLE).

-spec to_reserved(knm_numbers:collection()) -> knm_numbers:collection().
to_reserved(T0) -> ?TO_STATE2('to_reserved', T0).

to_reserved(T, ?NUMBER_STATE_RESERVED) ->
    knm_numbers:pipe(T
                    ,[fun not_assigning_to_self/1
                     ,fun authorize/1
                     ,fun update_reserve_history/1
                     ,fun move_to_reserved_state/1
                     ,fun knm_services:activate_phone_number/1
                     ,fun knm_carriers:acquire/1
                     ]);
to_reserved(T, ?NUMBER_STATE_DISCOVERY) ->
    knm_numbers:pipe(T
                    ,[fun authorize/1
                     ,fun update_reserve_history/1
                     ,fun move_to_reserved_state/1
                     ,fun knm_services:activate_phone_number/1
                     ,fun knm_carriers:acquire/1
                     ]);
to_reserved(T, ?NUMBER_STATE_AVAILABLE) ->
    knm_numbers:pipe(T
                    ,[fun authorize/1
                     ,fun update_reserve_history/1
                     ,fun move_to_reserved_state/1
                     ,fun knm_services:activate_phone_number/1
                     ]);
to_reserved(T, ?NUMBER_STATE_IN_SERVICE) ->
    knm_numbers:pipe(T
                    ,[fun authorize/1
                     ,fun update_reserve_history/1
                     ,fun move_to_reserved_state/1
                     ]);
to_reserved(T, State) ->
    invalid_state_transition(T, State, ?NUMBER_STATE_RESERVED).

-spec to_in_service(knm_numbers:collection()) -> knm_numbers:collection().
to_in_service(T0) -> ?TO_STATE2(to_in_service, T0).

to_in_service(T, ?NUMBER_STATE_IN_SERVICE) ->
    Ns = knm_numbers:todo(T),
    {Yes, No} = lists:partition(fun is_assigned_to_assignto/1, Ns),
    Ta = knm_numbers:ok(Yes, T),
    Tb = knm_numbers:pipe(knm_numbers:set_todo(T, No)
                         ,[fun authorize/1
                          ,fun move_to_in_service_state/1
                          ]),
    knm_numbers:merge_okkos(Ta, Tb);
to_in_service(T, ?NUMBER_STATE_DISCOVERY) ->
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_IN_SERVICE, ?NUMBER_STATE_DISCOVERY) end
                     ,fun authorize/1
                     ,fun move_to_in_service_state/1
                     ,fun knm_services:activate_phone_number/1
                     ,fun knm_carriers:acquire/1
                     ]);
to_in_service(T, ?NUMBER_STATE_PORT_IN) ->
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_IN_SERVICE, ?NUMBER_STATE_PORT_IN) end
                     ,fun authorize/1
                     ,fun move_to_in_service_state/1
                     ]);
to_in_service(T, ?NUMBER_STATE_AVAILABLE) ->
    %% Everyone MUST be allowed to buy available
    %% External carriers MUST NOT be contacted
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_IN_SERVICE, ?NUMBER_STATE_AVAILABLE) end
                     ,fun move_to_in_service_state/1
                     ,fun knm_services:activate_phone_number/1
                     ]);
to_in_service(T, ?NUMBER_STATE_RESERVED) ->
    knm_numbers:pipe(T
                    ,[fun (T0) -> fail_if_mdn(T0, ?NUMBER_STATE_IN_SERVICE, ?NUMBER_STATE_RESERVED) end
                     ,fun authorize_subaccount/1
                     ,fun move_to_in_service_state/1
                     ]);
to_in_service(T, State) ->
    invalid_state_transition(T, State, ?NUMBER_STATE_IN_SERVICE).

-spec authorize_subaccount(knm_numbers:collection()) -> knm_numbers:collection().
authorize_subaccount(T) ->
    knm_numbers:do_in_wrap(fun knm_phone_number:is_reserved_from_parent/1, T).

-spec authorize(knm_numbers:collection()) -> knm_numbers:collection().
authorize(T) ->
    knm_numbers:do_in_wrap(fun knm_phone_number:is_authorized/1, T).

-spec not_assigning_to_self(kn()) -> kn();
                           (knm_numbers:collection()) -> knm_numbers:collection().
not_assigning_to_self(T0) when is_map(T0) ->
    Ns = knm_numbers:todo(T0),
    F = fun (N, T) ->
                case knm_number:attempt(fun not_assigning_to_self/1, [N]) of
                    {ok, NewN} -> knm_numbers:ok(NewN, T);
                    {error, R} -> knm_numbers:ko(N, R, T)
                end
        end,
    lists:foldl(F, T0, Ns);
not_assigning_to_self(Number) ->
    PhoneNumber = knm_number:phone_number(Number),
    AssignedTo = knm_phone_number:assigned_to(PhoneNumber),
    case knm_phone_number:assign_to(PhoneNumber) of
        'undefined' -> knm_errors:unauthorized();
        AssignedTo -> knm_errors:no_change_required(Number);
        _AssignTo -> Number
    end.

-spec update_reserve_history(knm_numbers:collection()) -> knm_numbers:collection().
update_reserve_history(T) ->
    knm_numbers:do_in_wrap(fun knm_phone_number:push_reserve_history/1, T).

move_to_port_in_state(T) ->
    move_number_to_state(T, ?NUMBER_STATE_PORT_IN).
move_to_aging_state(T) ->
    move_number_to_state(T, ?NUMBER_STATE_AGING).
move_to_available_state(T) ->
    move_number_to_state(T, ?NUMBER_STATE_AVAILABLE).
move_to_reserved_state(T) ->
    move_number_to_state(T, ?NUMBER_STATE_RESERVED).
move_to_in_service_state(T) ->
    move_number_to_state(T, ?NUMBER_STATE_IN_SERVICE).

-spec move_number_to_state(kn(), ne_binary()) -> kn();
                          (knm_numbers:collection(), ne_binary()) -> knm_numbers:collection().
move_number_to_state(T, ToState) when is_map(T) ->
    Ns = knm_numbers:todo(T),
    NewNs = [move_number_to_state(N, ToState) || N <- Ns],
    knm_numbers:ok(NewNs, T);
move_number_to_state(Number, ToState) ->
    PhoneNumber = knm_number:phone_number(Number),
    {'ok', PN} = move_phone_number_to_state(PhoneNumber, ToState),
    knm_number:set_phone_number(Number, PN).

-spec move_phone_number_to_state(knm_phone_number:knm_phone_number(), ne_binary()) ->
                                        knm_phone_number_return().
move_phone_number_to_state(PN, ToState=?NUMBER_STATE_AVAILABLE) ->
    knm_phone_number:setters(PN, [{fun knm_phone_number:set_state/2, ToState}]);
move_phone_number_to_state(PN, ToState) ->
    AssignedTo = knm_phone_number:assigned_to(PN),
    move_phone_number_to_state(PN, ToState, AssignedTo).

-spec move_phone_number_to_state(knm_phone_number:knm_phone_number(), ne_binary(), api_binary()) ->
                                        knm_phone_number_return().
move_phone_number_to_state(PhoneNumber, ToState, 'undefined') ->
    Setters =
        [{fun knm_phone_number:set_assigned_to/2, knm_phone_number:assign_to(PhoneNumber)}
        ,{fun knm_phone_number:set_state/2, ToState}
        ],
    knm_phone_number:setters(PhoneNumber, Setters);
move_phone_number_to_state(PhoneNumber, ToState, AssignedTo) ->
    AssignTo = knm_phone_number:assign_to(PhoneNumber),
    move_phone_number_to_state(PhoneNumber, ToState, AssignedTo, AssignTo).

move_phone_number_to_state(PhoneNumber, ToState, AssignTo, AssignTo) ->
    Routines = [{fun knm_phone_number:set_state/2, ToState}
               ],
    knm_phone_number:setters(PhoneNumber, Routines);
move_phone_number_to_state(PhoneNumber, ToState, AssignedTo, AssignTo) ->
    Setters = [{fun knm_phone_number:set_assigned_to/2, AssignTo}
              ,{fun knm_phone_number:set_state/2, ToState}
              ],
    knm_phone_number:setters(PhoneNumber, Setters).


%% @private
-spec invalid_state_transition(knm_numbers:collection(), api_ne_binary(), ne_binary()) -> knm_numbers:collection().
invalid_state_transition(T, FromState, ToState) ->
    Ns = knm_numbers:todo(T),
    {'error', A, B, C} = (catch knm_errors:invalid_state_transition(undefined, FromState, ToState)),
    Reason = knm_errors:to_json(A, B, C),
    knm_numbers:ko(Ns, Reason, T).

%% @private
fail_if_mdn(T, ToState) ->
    Ns = knm_numbers:todo(T),
    case lists:partition(fun is_mdn/1, Ns) of
        {[], _} -> knm_numbers:ok(Ns, T);
        {MDNs, OtherNs} ->
            Ta = knm_numbers:ok(OtherNs, T),
            Tb = invalid_state_transition(knm_number:set_todo(T, MDNs), <<"'MDN'">>, ToState),
            knm_numbers:merge_okkos(Ta, Tb)
    end.

fail_if_mdn(T, FromState, ToState) ->
    Ns = knm_numbers:todo(T),
    case lists:partition(fun is_mdn/1, Ns) of
        {[], _} -> knm_numbers:ok(Ns, T);
        {MDNs, OtherNs} ->
            Ta = knm_numbers:ok(OtherNs, T),
            Tb = invalid_state_transition(knm_numbers:set_todo(T, MDNs), FromState, ToState),
            knm_numbers:merge_okkos(Ta, Tb)
    end.

%% @private
is_mdn(N) ->
    ?CARRIER_MDN =:= knm_phone_number:module_name(knm_number:phone_number(N)).

%% @private
is_assigned_to_assignto(N) ->
    PN = knm_number:phone_number(N),
    knm_phone_number:assign_to(PN)
        =:= knm_phone_number:assigned_to(PN).

%% @private
-spec group_by_state(knm_numbers:collection()) -> [{ne_binary(), knm_numbers:oks()}].
group_by_state(T) ->
    maps:to_list(
      lists:foldl(fun group_number_by_state/2, #{}, knm_numbers:todo(T))
     ).

-type group_by_acc() :: #{ne_binary() := knm_numbers:oks()}.
-spec group_number_by_state(knm_number:knm_number(), group_by_acc()) -> group_by_acc().
group_number_by_state(N, M) ->
    State = knm_phone_number:state(knm_number:phone_number(N)),
    AccNs = maps:get(State, M, []),
    M#{State => [N|AccNs]}.
