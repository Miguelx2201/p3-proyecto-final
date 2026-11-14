defmodule Emergencias.Servicios.NecesidadesServicio do
  @moduledoc """
  Consultas sobre colecciones de necesidades (funciones puras): filtrar,
  ordenar por prioridad y elegir la siguiente a atender.

  Recibe y devuelve listas de `Emergencias.Dominio.Necesidad`; no guarda estado
  ni modifica las necesidades.
  """

  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Servicios.Ordenamiento

  @doc """
  Devuelve las necesidades que cumplen **todos** los filtros, en el mismo orden
  en que llegaron.

  `filtros` es una keyword list con cualquier combinación de:

    * `zona:` código de zona (texto)
    * `tipo:` tipo de necesidad (átomo)
    * `prioridad:` prioridad (átomo)
    * `estado:` estado (átomo)

  Sin filtros (`[]`) devuelve todas. Una clave que no sea una de las cuatro
  anteriores se ignora.
  """
  @spec filtrar([Necesidad.t()], keyword()) :: [Necesidad.t()]
  def filtrar(necesidades, filtros) when is_list(necesidades) and is_list(filtros) do
    Enum.filter(necesidades, fn necesidad ->
      Enum.all?(filtros, &cumple?(necesidad, &1))
    end)
  end

  defp cumple?(%Necesidad{} = necesidad, {:zona, zona}), do: necesidad.zona == zona
  defp cumple?(%Necesidad{} = necesidad, {:tipo, tipo}), do: necesidad.tipo == tipo
  defp cumple?(%Necesidad{} = necesidad, {:prioridad, p}), do: necesidad.prioridad == p
  defp cumple?(%Necesidad{} = necesidad, {:estado, estado}), do: necesidad.estado == estado
  defp cumple?(_necesidad, _filtro_desconocido), do: true

  @doc """
  Ordena de mayor a menor prioridad (`Necesidad.peso_prioridad/1`). Si dos
  necesidades tienen la misma prioridad, va primero la más antigua (las fechas
  ISO 8601 se comparan como texto). Si también coinciden en fecha, conservan el
  orden de entrada.
  """
  @spec ordenar_por_prioridad([Necesidad.t()]) :: [Necesidad.t()]
  def ordenar_por_prioridad(necesidades) when is_list(necesidades),
    do: Ordenamiento.ordenar(necesidades, &antes_por_prioridad?/2)

  defp antes_por_prioridad?(%Necesidad{} = a, %Necesidad{} = b) do
    peso_a = Necesidad.peso_prioridad(a.prioridad)
    peso_b = Necesidad.peso_prioridad(b.prioridad)

    peso_a > peso_b or (peso_a == peso_b and a.fecha < b.fecha)
  end

  @doc """
  Necesidades en estado `:pendiente`, ordenadas por prioridad
  (ver `ordenar_por_prioridad/1`).
  """
  @spec pendientes([Necesidad.t()]) :: [Necesidad.t()]
  def pendientes(necesidades) when is_list(necesidades) do
    necesidades
    |> filtrar(estado: :pendiente)
    |> ordenar_por_prioridad()
  end

  @doc """
  La pendiente que debe atenderse primero: `{:ok, necesidad}`, o
  `{:error, :sin_pendientes}` si no hay ninguna.
  """
  @spec siguiente_a_atender([Necesidad.t()]) ::
          {:ok, Necesidad.t()} | {:error, :sin_pendientes}
  def siguiente_a_atender(necesidades) when is_list(necesidades) do
    case pendientes(necesidades) do
      [siguiente | _resto] -> {:ok, siguiente}
      [] -> {:error, :sin_pendientes}
    end
  end
end
