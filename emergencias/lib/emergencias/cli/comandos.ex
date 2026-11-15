defmodule Emergencias.CLI.Comandos do
  @moduledoc """
  Ejecuta un comando de la consola llamando a la fachada `Emergencias`.

  `ejecutar(sesion, comando, argumentos)` recibe:

    * `sesion`: `nil` (nadie conectado) o el `Usuario` conectado.
    * `comando`: átomo del comando (por ejemplo `:register_zone`).
    * `argumentos`: lista de valores **ya convertidos** por `Emergencias.CLI.Parser`.

  Devuelve lo mismo que la fachada: `:ok`, `{:ok, valor}` o `{:error, razon}`.
  Ninguna función lanza excepciones.

  ## Comandos de este módulo

    * `:connect` - `[usuario, contrasena, tipo, zona]`
    * `:disconnect` - `[]`
    * `:register_zone` - `[codigo, nombre, nivel]`
    * `:register_sector` - `[zona, codigo, nombre, personas]`
    * `:register_point` - `[zona, sector, codigo, nombre, personas]`
    * `:zone_status` - `[zona]`
    * `:zone_stats` - `[zona]`

  ## Errores propios

    * `{:error, {:argumentos, esperados: n}}`: cantidad de argumentos incorrecta.
    * `{:error, :no_conectado}`: comando que exige sesión y `sesion` es `nil`.
    * `{:error, :ya_conectado}`: `connect` con una sesión ya iniciada.
    * `{:error, :no_implementado}`: comando que todavía no tiene cláusula aquí.
  """

  alias Emergencias.Dominio.Usuario

  # Comando => cantidad de argumentos que espera.
  @aridad %{
    connect: 4,
    disconnect: 0,
    register_zone: 3,
    register_sector: 4,
    register_point: 5,
    zone_status: 1,
    zone_stats: 1
  }

  @doc "Ejecuta `comando` con `argumentos` en nombre de `sesion`."
  def ejecutar(sesion, comando, argumentos) when is_list(argumentos) do
    case Map.fetch(@aridad, comando) do
      {:ok, esperados} when length(argumentos) == esperados ->
        despachar(sesion, comando, argumentos)

      {:ok, esperados} ->
        {:error, {:argumentos, esperados: esperados}}

      :error ->
        {:error, :no_implementado}
    end
  end

  def ejecutar(_sesion, _comando, _argumentos), do: {:error, :valor_invalido}

  # --- sesión ----------------------------------------------------------------

  defp despachar(nil, :connect, [username, password, tipo, zona]),
    do: Emergencias.connect(username, password, tipo, zona)

  defp despachar(%Usuario{}, :connect, _argumentos), do: {:error, :ya_conectado}

  # Todo lo demás exige sesión.
  defp despachar(nil, _comando, _argumentos), do: {:error, :no_conectado}

  defp despachar(%Usuario{} = usuario, :disconnect, []), do: Emergencias.disconnect(usuario)

  # --- zonas -----------------------------------------------------------------

  defp despachar(%Usuario{} = usuario, :register_zone, [codigo, nombre, nivel]),
    do: Emergencias.register_zone(usuario, codigo, nombre, nivel)

  defp despachar(%Usuario{} = usuario, :register_sector, [zona, codigo, nombre, personas]),
    do: Emergencias.register_sector(usuario, zona, codigo, nombre, personas)

  defp despachar(%Usuario{} = usuario, :register_point, [zona, sector, codigo, nombre, personas]),
    do: Emergencias.register_point(usuario, zona, sector, codigo, nombre, personas)

  defp despachar(%Usuario{} = usuario, :zone_status, [zona]),
    do: Emergencias.zone_status(usuario, zona)

  defp despachar(%Usuario{} = usuario, :zone_stats, [zona]),
    do: Emergencias.zone_stats(usuario, zona)

  defp despachar(_otra_sesion, _comando, _argumentos), do: {:error, :usuario_invalido}
end
