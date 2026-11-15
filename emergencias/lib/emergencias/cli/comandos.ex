defmodule Emergencias.CLI.Comandos do
  @moduledoc """
  Ejecuta un comando ya parseado.

  **Versión mínima del issue #29.** Solo implementa `connect` y `disconnect`,
  que el bucle necesita para abrir y cerrar sesión. Los issues #30 a #32 la
  reemplazan agregando una cláusula por comando; el contrato no cambia.

  ## Contrato

  `ejecutar(sesion, comando, argumentos)` recibe la sesión (`nil` o el
  `Usuario` conectado), el átomo del comando y los argumentos ya convertidos
  por `Emergencias.CLI.Parser`. Devuelve:

    * `{:ok, valor}` o `:ok` si todo salió bien (`connect` devuelve
      `{:ok, usuario}` con el usuario conectado; `disconnect` devuelve `:ok`);
    * `{:error, razon}` con `razon` átomo si falló.

  El bucle (`Emergencias.CLI`) ya garantiza que, salvo `connect`, siempre hay
  sesión; por eso este módulo no vuelve a validarlo.

  Nunca debe llegar aquí `help` ni `exit`: los resuelve el bucle.
  """

  alias Emergencias.Dominio.Usuario

  @doc "Ejecuta el comando. Ver el contrato en el módulo."
  def ejecutar(sesion, comando, argumentos)

  def ejecutar(_sesion, :connect, [usuario, contrasena, tipo, zona]),
    do: Emergencias.connect(usuario, contrasena, tipo, zona)

  def ejecutar(%Usuario{} = sesion, :disconnect, []), do: Emergencias.disconnect(sesion)

  def ejecutar(_sesion, _comando, _argumentos), do: {:error, :no_implementado}
end
