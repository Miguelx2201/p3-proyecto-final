defmodule Emergencias.CLI do
  @moduledoc """
  Bucle de la consola.

  Se inicia con:

      mix run -e "Emergencias.CLI.iniciar()"

  Cada línea sigue este flujo:

      Parser.parsear/1 -> Comandos.ejecutar/3 -> Formato.a_texto/1 -> imprimir

  `help` y `exit` los resuelve el bucle (no pasan por `Comandos`). La sesión es
  `nil` (nadie conectado) o el `Usuario` conectado; sin sesión solo se aceptan
  `connect`, `help` y `exit`, y cualquier otro comando da
  `{:error, :no_conectado}`.

  La consola no termina por una entrada inválida ni por un fallo dentro de un
  comando: el error se muestra y se vuelve a pedir una línea. Solo termina con
  `exit` o al cerrarse la entrada (`:eof`), y en ambos casos desconecta al
  usuario si había sesión.
  """

  require Logger

  alias Emergencias.CLI.Comandos
  alias Emergencias.CLI.Formato
  alias Emergencias.CLI.Parser
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Util

  @doc "Inicia la consola sin sesión. Devuelve `:ok` al salir."
  def iniciar do
    imprimir(Formato.bienvenida())
    bucle(nil)
  end

  @doc """
  Procesa una línea con la sesión actual, sin imprimir nada.

  Devuelve `{:continuar, nueva_sesion, texto}` o `{:salir, texto}`. Nunca lanza
  excepciones: un fallo inesperado se registra en el log y se convierte en
  `{:error, :error_interno}`.
  """
  def procesar(sesion, linea) do
    procesar_linea(sesion, linea)
  rescue
    excepcion ->
      Logger.error("Fallo inesperado en la consola: " <> Exception.message(excepcion))
      {:continuar, sesion, Formato.a_texto({:error, :error_interno})}
  catch
    tipo, razon ->
      Logger.error("Fallo inesperado en la consola: " <> inspect({tipo, razon}))
      {:continuar, sesion, Formato.a_texto({:error, :error_interno})}
  end

  # ---------------------------------------------------------------------------
  # Bucle
  # ---------------------------------------------------------------------------

  defp bucle(sesion) do
    case IO.gets("> ") do
      linea when is_binary(linea) ->
        case procesar(sesion, linea) do
          {:continuar, nueva_sesion, texto} ->
            imprimir(texto)
            bucle(nueva_sesion)

          {:salir, texto} ->
            imprimir(texto)
        end

      _fin ->
        # `:eof` o error de lectura: no hay forma de seguir leyendo.
        {:salir, texto} = cerrar(sesion)
        imprimir("\n" <> texto)
    end
  end

  defp imprimir(""), do: :ok
  defp imprimir(texto), do: Util.mostrar_mensaje(texto)

  # ---------------------------------------------------------------------------
  # Una línea
  # ---------------------------------------------------------------------------

  defp procesar_linea(sesion, linea) do
    case Parser.parsear(linea) do
      {:ok, {comando, argumentos}} -> ejecutar(sesion, comando, argumentos)
      {:error, _razon} = error -> {:continuar, sesion, Formato.a_texto(error)}
    end
  end

  defp ejecutar(sesion, :exit, _argumentos), do: cerrar(sesion)

  defp ejecutar(sesion, :help, _argumentos), do: {:continuar, sesion, Formato.ayuda(sesion)}

  # Sin sesión solo `connect`, `help` y `exit` (los dos últimos ya se atendieron).
  defp ejecutar(nil, comando, _argumentos) when comando != :connect,
    do: {:continuar, nil, Formato.a_texto({:error, :no_conectado})}

  defp ejecutar(nil, :connect, argumentos) do
    case Comandos.ejecutar(nil, :connect, argumentos) do
      {:ok, %Usuario{} = usuario} -> {:continuar, usuario, Formato.a_texto({:ok, usuario})}
      resultado -> {:continuar, nil, Formato.a_texto(resultado)}
    end
  end

  defp ejecutar(%Usuario{} = sesion, :connect, _argumentos),
    do: {:continuar, sesion, Formato.a_texto({:error, :ya_conectado})}

  defp ejecutar(%Usuario{} = sesion, :disconnect, argumentos) do
    case Comandos.ejecutar(sesion, :disconnect, argumentos) do
      :ok -> {:continuar, nil, Formato.sesion_cerrada()}
      resultado -> {:continuar, sesion, Formato.a_texto(resultado)}
    end
  end

  defp ejecutar(sesion, comando, argumentos) do
    resultado = Comandos.ejecutar(sesion, comando, argumentos)
    {:continuar, sesion, Formato.a_texto(resultado)}
  end

  # ---------------------------------------------------------------------------
  # Salida
  # ---------------------------------------------------------------------------

  defp cerrar(nil), do: {:salir, Formato.despedida()}

  defp cerrar(sesion) do
    _resultado = desconectar(sesion)
    {:salir, Formato.sesion_cerrada() <> "\n" <> Formato.despedida()}
  end

  # Si la desconexión falla igual se sale: no se puede dejar al usuario atrapado.
  defp desconectar(sesion) do
    Comandos.ejecutar(sesion, :disconnect, [])
  rescue
    _excepcion -> {:error, :error_interno}
  catch
    _tipo, _razon -> {:error, :error_interno}
  end
end
