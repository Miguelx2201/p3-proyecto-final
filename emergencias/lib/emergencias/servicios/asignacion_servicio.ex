defmodule Emergencias.Servicios.AsignacionServicio do
  @moduledoc """
  Lógica pura para repartir recursos entre necesidades y transferirlos entre
  centros.

  Este módulo no guarda estado ni hace entrada/salida: recibe listas y structs
  y devuelve listas y structs nuevos. La garantía de que nunca se supere el
  inventario la da el GenServer de recursos, que ejecuta estas funciones de a
  una llamada por vez.

  Ninguna función lanza excepciones: devuelven `{:ok, valor}` o
  `{:error, razon}`. Cada operación es todo o nada: si falla, el llamador
  conserva sus datos originales sin cambios.

  Los movimientos que se devuelven tienen `id` en `nil`; el servidor de
  recursos se los asigna antes de guardarlos.
  """

  alias Emergencias.Dominio.{Movimiento, Necesidad, Recurso}
  alias Emergencias.Util

  # ---------------------------------------------------------------------------
  # Reserva
  # ---------------------------------------------------------------------------

  @doc """
  Reserva `cantidad` unidades de la `categoria` indicada, tomándolas de los
  `recursos` en orden (si el primero no alcanza, sigue con el siguiente).

  `recursos` son los candidatos ya filtrados por zona. Devuelve
  `{:ok, %{recursos: actualizados, movimientos: movimientos}}`:

    * `recursos` conserva todos los candidatos en su orden original; solo
      cambian los que se usaron.
    * `movimientos` tiene un movimiento `:asignacion` por cada recurso usado,
      con `referencia` igual a `necesidad_id`.

  Errores: `:cantidad_invalida` (no es un entero mayor que 0), `:sin_stock`
  (la suma disponible de la categoría no alcanza) y los errores de
  `Movimiento.nuevo/5` (por ejemplo `:texto_vacio` si `usuario` está vacío).
  Es todo o nada: si no alcanza, ningún recurso cambia.
  """
  @spec reservar([Recurso.t()], atom(), integer(), String.t() | nil, String.t()) ::
          {:ok, %{recursos: [Recurso.t()], movimientos: [Movimiento.t()]}}
          | {:error, atom()}
  def reservar(recursos, categoria, cantidad, necesidad_id, usuario) when is_list(recursos) do
    acumulado = %{
      categoria: categoria,
      necesidad_id: necesidad_id,
      usuario: usuario,
      recursos: [],
      movimientos: []
    }

    with :ok <- validar_cantidad(cantidad),
         :ok <- validar_stock(recursos, categoria, cantidad),
         {:ok, resultado} <- tomar(recursos, cantidad, acumulado) do
      {:ok, %{recursos: resultado.recursos, movimientos: resultado.movimientos}}
    end
  end

  # Recorre los recursos tomando del primero lo que pueda hasta que `restante`
  # llegue a 0. `acumulado` lleva los datos de la reserva (categoria,
  # necesidad_id, usuario) y lo construido hasta ahora (recursos y movimientos,
  # en orden inverso mientras se recorre).
  #
  # Cuando `restante` es 0, el resto de los recursos pasa sin cambios.
  defp tomar(resto, 0, acumulado), do: {:ok, cerrar(acumulado, resto)}

  # No debería ocurrir porque `reservar/5` verifica el stock antes; protege
  # la recursión ante un uso incorrecto.
  defp tomar([], _restante, _acumulado), do: {:error, :sin_stock}

  defp tomar([recurso | resto], restante, acumulado) do
    if recurso.categoria == acumulado.categoria and recurso.cantidad_disponible > 0 do
      tomar_de(recurso, resto, restante, acumulado)
    else
      tomar(resto, restante, %{acumulado | recursos: [recurso | acumulado.recursos]})
    end
  end

  defp tomar_de(recurso, resto, restante, acumulado) do
    tomado = min(recurso.cantidad_disponible, restante)

    with {:ok, actualizado} <- Recurso.salida(recurso, tomado),
         {:ok, movimiento} <-
           Movimiento.nuevo(
             recurso.id,
             :asignacion,
             tomado,
             acumulado.usuario,
             acumulado.necesidad_id
           ) do
      acumulado = %{
        acumulado
        | recursos: [actualizado | acumulado.recursos],
          movimientos: [movimiento | acumulado.movimientos]
      }

      tomar(resto, restante - tomado, acumulado)
    end
  end

  defp cerrar(acumulado, resto) do
    %{
      acumulado
      | recursos: Enum.reverse(acumulado.recursos, resto),
        movimientos: Enum.reverse(acumulado.movimientos)
    }
  end

  defp validar_stock(recursos, categoria, cantidad) do
    disponible =
      recursos
      |> Enum.filter(&(&1.categoria == categoria))
      |> Enum.reduce(0, fn recurso, suma -> suma + recurso.cantidad_disponible end)

    if disponible >= cantidad, do: :ok, else: {:error, :sin_stock}
  end

  # ---------------------------------------------------------------------------
  # Asignación completa
  # ---------------------------------------------------------------------------

  @doc """
  Flujo completo: reserva `cantidad` de la categoría de la necesidad (su
  `tipo`) con `reservar/5` y luego la registra en la necesidad con
  `Necesidad.registrar_asignacion/2`.

  Devuelve `{:ok, %{necesidad: necesidad, recursos: recursos, movimientos: movimientos}}`.

  Errores: los de `reservar/5` y los de `Necesidad.registrar_asignacion/2`
  (`:ya_cerrada`, `:excede_requerido`, `:cantidad_invalida`). Si algo falla no
  se devuelve ningún cambio.
  """
  @spec asignar(Necesidad.t(), [Recurso.t()], integer(), String.t()) ::
          {:ok,
           %{
             necesidad: Necesidad.t(),
             recursos: [Recurso.t()],
             movimientos: [Movimiento.t()]
           }}
          | {:error, atom()}
  def asignar(%Necesidad{} = necesidad, recursos, cantidad, usuario) do
    with {:ok, %{recursos: actualizados, movimientos: movimientos}} <-
           reservar(recursos, necesidad.tipo, cantidad, necesidad.id, usuario),
         {:ok, necesidad_nueva} <- Necesidad.registrar_asignacion(necesidad, cantidad) do
      {:ok, %{necesidad: necesidad_nueva, recursos: actualizados, movimientos: movimientos}}
    end
  end

  # ---------------------------------------------------------------------------
  # Transferencia
  # ---------------------------------------------------------------------------

  @doc """
  Transfiere `cantidad` unidades del recurso `origen` al centro
  `centro_destino`.

  Si `destino` es `nil` se crea un recurso nuevo con el mismo nombre,
  categoría, unidad y zona del origen, `ubicacion` igual a `centro_destino` e
  id `"\#{origen.id}-\#{centro_destino}"`. Si `destino` es un recurso, recibe
  la cantidad; debe ser compatible con el origen (misma categoría, unidad y
  zona, y `ubicacion` igual a `centro_destino`).

  Devuelve `{:ok, %{origen: origen, destino: destino, movimientos: movimientos}}`.
  `movimientos` es `[salida, entrada]`: un `:transferencia_salida` sobre el
  origen (referencia: el centro de destino) y un `:transferencia_entrada`
  sobre el destino (referencia: la ubicación del origen).

  Errores:

    * `:cantidad_invalida`: no es un entero mayor que 0.
    * `:mismo_centro`: el destino está en el mismo centro que el origen.
    * `:destino_invalido`: el destino existente no es compatible con el origen
      (otra categoría, unidad o zona, o su ubicación no es `centro_destino`).
      Las transferencias entre zonas distintas no se soportan.
    * `:sin_stock`: el origen no tiene `cantidad` disponible.
    * Errores de `Recurso.crear/7` y `Movimiento.nuevo/5` (por ejemplo
      `:texto_vacio` si `centro_destino` o `usuario` están vacíos).
  """
  @spec transferir(Recurso.t(), Recurso.t() | nil, integer(), String.t(), String.t()) ::
          {:ok, %{origen: Recurso.t(), destino: Recurso.t(), movimientos: [Movimiento.t()]}}
          | {:error, atom()}
  def transferir(%Recurso{} = origen, destino, cantidad, centro_destino, usuario)
      when is_nil(destino) or is_struct(destino, Recurso) do
    centro = Util.sanitizar_texto(centro_destino)

    with :ok <- validar_cantidad(cantidad),
         :ok <- validar_mismo_centro(origen, destino, centro),
         {:ok, destino} <- preparar_destino(origen, destino, centro),
         {:ok, origen_nuevo} <- Recurso.salida(origen, cantidad),
         {:ok, destino_nuevo} <- Recurso.entrada(destino, cantidad),
         {:ok, salida} <-
           Movimiento.nuevo(origen.id, :transferencia_salida, cantidad, usuario, centro),
         {:ok, entrada} <-
           Movimiento.nuevo(
             destino.id,
             :transferencia_entrada,
             cantidad,
             usuario,
             origen.ubicacion
           ) do
      {:ok, %{origen: origen_nuevo, destino: destino_nuevo, movimientos: [salida, entrada]}}
    end
  end

  defp validar_mismo_centro(origen, nil, centro) do
    if centro == origen.ubicacion, do: {:error, :mismo_centro}, else: :ok
  end

  defp validar_mismo_centro(origen, %Recurso{} = destino, centro) do
    if centro == origen.ubicacion or destino.ubicacion == origen.ubicacion,
      do: {:error, :mismo_centro},
      else: :ok
  end

  # Sin destino: crea uno vacío con los datos del origen.
  defp preparar_destino(origen, nil, centro) do
    Recurso.crear(
      "#{origen.id}-#{centro}",
      origen.nombre,
      origen.categoria,
      0,
      origen.unidad,
      centro,
      origen.zona
    )
  end

  defp preparar_destino(origen, %Recurso{} = destino, centro) do
    if destino.categoria == origen.categoria and destino.unidad == origen.unidad and
         destino.zona == origen.zona and destino.ubicacion == centro,
       do: {:ok, destino},
       else: {:error, :destino_invalido}
  end

  # ---------------------------------------------------------------------------
  # Validaciones compartidas
  # ---------------------------------------------------------------------------

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: :ok
  defp validar_cantidad(_otra), do: {:error, :cantidad_invalida}
end
