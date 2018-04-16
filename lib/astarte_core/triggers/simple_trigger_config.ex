defmodule Astarte.Core.Triggers.SimpleTriggerConfig do
  @moduledoc """
  This module handles the functions for creating a `SimpleTriggerConfig` and converting it to and from a `TaggedSimpleTrigger`.
  """
  use Astarte.Core.Triggers.SimpleTriggersProtobuf
  use Ecto.Schema

  import Ecto.Changeset
  alias Astarte.Core.CQLUtils
  alias Astarte.Core.Device
  alias Astarte.Core.Triggers.SimpleTriggerConfig

  @primary_key false
  embedded_schema do
    # Common
    field :type, :string
    field :on, :string
    # Data Trigger specific
    field :interface_name, :string
    field :interface_major, :integer
    field :value_match_operator, :string
    field :match_path, :string
    field :known_value, :any, virtual: true
    # Device trigger specific
    field :device_id, :string
  end

  defimpl Poison.Encoder, for: SimpleTriggerConfig do
    def encode(%SimpleTriggerConfig{type: "data_trigger"} = config, options) do
      config_map =
        if config.value_match_operator != "*" do
          %{"type" => config.type,
            "on" => config.on,
            "interface_name" => config.interface_name,
            "interface_major" => config.interface_major,
            "value_match_operator" => config.value_match_operator,
            "match_path" => config.match_path,
            "known_value" => config.known_value
          }
        else
          %{"type" => config.type,
            "on" => config.on,
            "interface_name" => config.interface_name,
            "interface_major" => config.interface_major,
            "value_match_operator" => config.value_match_operator
          }
        end

      Poison.Encoder.Map.encode(config_map, options)
    end

    def encode(%SimpleTriggerConfig{type: "device_trigger"} = config, options) do
      %{"type" => config.type,
        "on" => config.on,
        "device_id" => config.device_id,
      }
      |> Poison.Encoder.Map.encode(options)
    end
  end

  @data_trigger_permitted_keys [
    :type,
    :interface_name,
    :interface_major,
    :on,
    :value_match_operator,
    :match_path,
    :known_value
  ]
  @data_trigger_required_keys [
    :type,
    :interface_name,
    :interface_major,
    :on,
    :value_match_operator
  ]
  @data_trigger_condition_to_atom %{
    "incoming_data" => :INCOMING_DATA,
    "value_change" => :VALUE_CHANGE,
    "value_change_applied" => :VALUE_CHANGE_APPLIED,
    "path_created" => :PATH_CREATED,
    "path_removed" => :PATH_REMOVED,
    "value_stored" => :VALUE_STORED
  }
  @data_trigger_condition_to_string %{
    :INCOMING_DATA => "incoming_data",
    :VALUE_CHANGE => "value_change",
    :VALUE_CHANGE_APPLIED => "value_change_applied",
    :PATH_CREATED => "path_created",
    :PATH_REMOVED => "path_removed",
    :VALUE_STORED => "value_stored"
  }
  @data_trigger_operator_to_atom %{
    "*" => :ANY,
    "==" => :EQUAL_TO,
    "!=" => :NOT_EQUAL_TO,
    ">" => :GREATER_THAN,
    ">=" => :GREATER_OR_EQUAL_TO,
    "<" => :LESS_THAN,
    "<=" => :LESS_OR_EQUAL_TO,
    "contains" => :CONTAINS,
    "not_contains" => :NOT_CONTAINS
  }
  @data_trigger_operator_to_string %{
    :ANY => "*",
    :EQUAL_TO => "==",
    :NOT_EQUAL_TO => "!=",
    :GREATER_THAN => ">",
    :GREATER_OR_EQUAL_TO => ">=",
    :LESS_THAN => "<",
    :LESS_OR_EQUAL_TO => "<=",
    :CONTAINS => "contains",
    :NOT_CONTAINS => "not_contains"
  }
  @data_trigger_any_match_operator "*"

  @device_trigger_keys [
    :type,
    :on,
    :device_id
  ]
  @device_trigger_condition_to_atom %{
    "device_connected" => :DEVICE_CONNECTED,
    "device_disconnected" => :DEVICE_DISCONNECTED,
    "device_empty_cache_received" => :DEVICE_EMPTY_CACHE_RECEIVED,
    "device_error" => :DEVICE_ERROR
  }
  @device_trigger_condition_to_string %{
    :DEVICE_CONNECTED => "device_connected",
    :DEVICE_DISCONNECTED => "device_disconnected",
    :DEVICE_EMPTY_CACHE_RECEIVED => "device_empty_cache_received",
    :DEVICE_ERROR => "device_error"
  }

  @allowed_trigger_types [
    "data_trigger",
    "device_trigger"
  ]

  @doc false
  def changeset(
        %SimpleTriggerConfig{} = simple_trigger_config,
        %{"type" => "data_trigger"} = params
      ) do
    simple_trigger_config
    |> cast(params, @data_trigger_permitted_keys)
    |> validate_required(@data_trigger_required_keys)
    |> validate_inclusion(:on, Map.keys(@data_trigger_condition_to_atom))
    |> validate_inclusion(:value_match_operator, Map.keys(@data_trigger_operator_to_atom))
    |> validate_match_parameters()

    # TODO: add further validation (e.g. interface name and mapping regex validation)
  end

  def changeset(
        %SimpleTriggerConfig{} = simple_trigger_config,
        %{"type" => "device_trigger"} = params
      ) do
    simple_trigger_config
    |> cast(params, @device_trigger_keys)
    |> validate_required(@device_trigger_keys)
    |> validate_inclusion(:on, Map.keys(@device_trigger_condition_to_atom))
    |> validate_and_decode_device_id(:device_id)
  end

  def changeset(%SimpleTriggerConfig{} = simple_trigger_config, params) when is_map(params) do
    # If we're here, "type" is either missing or invalid
    # This will return an error changeset with the appropriate message
    simple_trigger_config
    |> cast(params, [:type])
    |> validate_required([:type])
    |> validate_inclusion(:type, @allowed_trigger_types)
  end

  @doc """
  Creates a `TaggedSimpleTrigger` from a `SimpleTriggerConfig`.

  It is assumed that the `SimpleTriggerConfig` is valid and constructed using `SimpleTriggerConfig.changeset`

  Returns a `%TaggedSimpleTrigger{}`
  """
  def to_tagged_simple_trigger(%SimpleTriggerConfig{type: "data_trigger"} = simple_trigger_config) do
    simple_trigger_config
    |> put_data_trigger_atoms()
    |> create_tagged_data_trigger()
  end

  def to_tagged_simple_trigger(
        %SimpleTriggerConfig{type: "device_trigger"} = simple_trigger_config
      ) do
    simple_trigger_config
    |> put_device_trigger_atoms()
    |> create_tagged_device_trigger()
  end

  def from_tagged_simple_trigger(%TaggedSimpleTrigger{} = tagged_simple_trigger) do
    %TaggedSimpleTrigger{
      object_id: object_id,
      simple_trigger_container: simple_trigger_container
    } = tagged_simple_trigger

    case simple_trigger_container.simple_trigger do
      {:data_trigger, %DataTrigger{} = data_trigger} ->
        from_data_trigger(data_trigger)

      {:device_trigger, %DeviceTrigger{} = device_trigger} ->
        from_device_trigger(device_trigger, object_id)
    end
  end

  defp validate_match_parameters(%Ecto.Changeset{} = changeset) do
    if get_field(changeset, :value_match_operator) == @data_trigger_any_match_operator do
      changeset
      |> delete_change(:match_path)
      |> delete_change(:known_value)
    else
      changeset
      |> validate_required([:match_path, :known_value])
    end
  end

  defp validate_and_decode_device_id(%Ecto.Changeset{} = changeset, field) do
    with {:ok, encoded_id} <- fetch_change(changeset, field),
         {:ok, decoded_id} <- Device.decode_device_id(encoded_id) do
      put_change(changeset, field, decoded_id)
    else
      :error ->
        # fetch_change failes, so the changeset is already invalid
        changeset

      {:error, :invalid_device_id} ->
        # decode_device_id failed
        add_error(changeset, field, "is not a valid device id")

      {:error, :extended_id_not_allowed} ->
        # extended id
        add_error(changeset, field, "is too long, device id must be 128 bits")
    end
  end

  defp put_data_trigger_atoms(%{on: condition, value_match_operator: operator} = params) do
    condition_atom = Map.get(@data_trigger_condition_to_atom, condition)
    operator_atom = Map.get(@data_trigger_operator_to_atom, operator)
    %{params | on: condition_atom, value_match_operator: operator_atom}
  end

  defp put_device_trigger_atoms(%{on: condition} = params) do
    condition_atom = Map.get(@device_trigger_condition_to_atom, condition)
    %{params | on: condition_atom}
  end

  defp create_tagged_data_trigger(%SimpleTriggerConfig{} = config) do
    %SimpleTriggerConfig{
      interface_name: interface_name,
      interface_major: interface_major,
      match_path: match_path,
      known_value: known_value,
      on: trigger_type,
      value_match_operator: value_match_operator
    } = config

    interface_id = CQLUtils.interface_id(interface_name, interface_major)

    data_trigger = %DataTrigger{
      interface_id: interface_id,
      known_value: known_value && Bson.encode(%{v: known_value}),
      match_path: match_path,
      data_trigger_type: trigger_type,
      value_match_operator: value_match_operator
    }

    %TaggedSimpleTrigger{
      # TODO: object_type 2 is interface, it should be a constant
      object_type: 2,
      object_id: interface_id,
      simple_trigger_container: %SimpleTriggerContainer{
        simple_trigger: {:data_trigger, data_trigger}
      }
    }
  end

  defp create_tagged_device_trigger(%SimpleTriggerConfig{} = config) do
    %SimpleTriggerConfig{
      on: event_type,
      device_id: device_id
    } = config

    device_trigger = %DeviceTrigger{
      device_event_type: event_type
    }

    %TaggedSimpleTrigger{
      # TODO: object_type 1 is device, it should be a constant
      object_type: 1,
      object_id: device_id,
      simple_trigger_container: %SimpleTriggerContainer{
        simple_trigger: {:device_trigger, device_trigger}
      }
    }
  end

  defp from_data_trigger(%DataTrigger{} = data_trigger) do
    %DataTrigger{
      data_trigger_type: data_trigger_type,
      interface_id: _interface_id,
      value_match_operator: value_match_operator,
      match_path: match_path,
      known_value: known_value
    } = data_trigger

    condition = Map.fetch!(@data_trigger_condition_to_string, data_trigger_type)
    value_match_operator_string = Map.fetch!(@data_trigger_operator_to_string, value_match_operator)
    decoded_known_value =
      if known_value do
        Bson.decode(known_value)
        |> Map.get(:v)
      else
        nil
      end

    # TODO: interface_name and interface_major can't be deducted from interface_id,
    # leaving them nil waiting for an API to retrieve them
    %SimpleTriggerConfig{
      type: "data_trigger",
      on: condition,
      interface_name: nil,
      interface_major: nil,
      value_match_operator: value_match_operator_string,
      match_path: match_path,
      known_value: decoded_known_value
    }
  end

  defp from_device_trigger(%DeviceTrigger{} = device_trigger, device_id) do
    %DeviceTrigger{
      device_event_type: device_event_type
    } = device_trigger

    encoded_device_id = Device.encode_device_id(device_id)

    condition = Map.fetch!(@device_trigger_condition_to_string, device_event_type)

    %SimpleTriggerConfig{
      type: "device_trigger",
      on: condition,
      device_id: encoded_device_id
    }
  end
end
