-- CASO 1:
SELECT * FROM CONSUMO;
SELECT * FROM total_consumos;
SELECT * FROM huesped;

CREATE OR REPLACE TRIGGER trg_mantener_total_huesped
AFTER INSERT OR UPDATE OR DELETE ON consumo
FOR EACH ROW

BEGIN
    IF INSERTING THEN 
        UPDATE total_consumos
        SET monto_consumos = monto_consumos + NEW.monto
        WHERE id_huesped = :NEW.id_huesped;
    
    ELSIF UPDATING THEN 
        UPDATE total_consumos
        SET monto_consumos = (monto_consumos - :OLD.monto) + :NEW.monto
        WHERE id_huesped = :NEW.id_huesped;
        
    ELSIF DELETING THEN
        UPDATE total_consumos
        SET monto_consumos = monto_consumos - :OLD.monto
        WHERE id_huesped = :OLD.id_huesped;
    END IF;
END;
/

DECLARE
--VARIABLE PARA EL NUEVO ID CONSUMO
    v_new_consumo NUMBER;

BEGIN
--OBTENER SIGUIENTE ID DE CONSUMO
    SELECT MAX(id_consumo)+1
    INTO v_new_consumo
    FROM CONSUMO;
    
-- INSERTAR NUEVO CONSUMO
    INSERT INTO CONSUMO (id_consumo,id_reserva,id_huesped,monto)
    VALUES(v_new_consumo,1587,340006,150);
    
--ELIMINAR CONSUMO CON ID 11473
    DELETE FROM CONSUMO
    WHERE id_consumo = 11473;
    
--ACTUALIZAR CONSUMO 10688
    UPDATE CONSUMO
    SET monto = 95
    WHERE id_consumo = 10688;
    
    COMMIT;       
END;
/

-- CASO 2:
SELECT * FROM TOUR;

--PACKAGE 
CREATE OR REPLACE PACKAGE pkg_constructores AS

--FUNCION PARA DETERMINAR MONTO QUE DEBE PAGAR EL HUESPED POR TOUR / SI NO HA TOMADO TOUR DEBE DEVOLVER 0
FUNCTION fn_total_tours
(p_id_huesped NUMBER)
RETURN NUMBER;

 -- VARIABLE PUBLICA (OPCIONAL) PARA CALCULAR EL TOTAL DE TOURS
 v_total_tours NUMBER;

END pkg_constructores;
/

--BODY PACKAGE
 CREATE OR REPLACE PACKAGE BODY pkg_constructores IS
 
 FUNCTION fn_total_tours
 (p_id_huesped NUMBER)
 RETURN NUMBER
 IS
 -- VARIABLE PARA CALCULAR EL TOTAL DE TOURS
 v_monto NUMBER := 0;
 
 BEGIN 
    SELECT NVL(SUM(t.valor_tour),0)
    INTO v_monto
    FROM TOUR t
    JOIN HUESPED_TOUR ht
    ON t.id_tour = ht.id_tour
    WHERE ht.id_huesped = p_id_huesped;
    
    v_total_tours := v_monto;
    
    RETURN v_total_tours;
    
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 0;
        WHEN OTHERS THEN
            RETURN 0;
END fn_total_tours;
               
END pkg_constructores;
/

--FUNCION ALMACENADA QUE RETORNA LA AGENCIA DE LA CUAL PROCEDE EL HUESPED:

CREATE OR REPLACE FUNCTION fn_agencia
    (p_id_huesped NUMBER)
RETURN VARCHAR2
IS
    v_agencia agencia.nom_agencia%TYPE;
    v_error VARCHAR2(200);
BEGIN

    SELECT a.nom_agencia
    INTO v_agencia
    FROM huesped h
    JOIN agencia a
    ON h.id_agencia = a.id_agencia
    WHERE h.id_huesped = p_id_huesped;

    RETURN v_agencia;
    
EXCEPTION   
    WHEN NO_DATA_FOUND THEN
        v_error := SQLERRM;
    
        INSERT INTO REG_ERRORES(id_error, nomsubprograma, msg_error)
        VALUES(
            SQ_ERROR.NEXTVAL,
            'fn_agencia',
            v_error 
            );
        RETURN 'NO REGISTRA AGENCIA';
        
    WHEN OTHERS THEN
        v_error := SQLERRM;
        
        INSERT INTO REG_ERRORES(id_error, nomsubprograma, msg_error)
        VALUES (
            SQ_ERROR.NEXTVAL,
            'fn_obtener_agencia',
            v_error
        );

        RETURN 'NO REGISTRA AGENCIA';

END fn_agencia;
/

--FUNCION ALMACENADA QUE DETERMINA MONTO EN DOLARES DE LOS CONSUMOS DEL HUESPED

CREATE OR REPLACE FUNCTION fn_consumos_huesped
    (p_id_huesped NUMBER)
RETURN NUMBER
IS
    v_consumos_huesped NUMBER;
    
BEGIN
    SELECT monto_consumos
    INTO v_consumos_huesped
    FROM total_consumos
    WHERE id_huesped = p_id_huesped;
    
    RETURN v_consumos_huesped;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
        
    WHEN OTHERS THEN
        RETURN 0;

END fn_consumos_huesped;
/

SET SERVEROUTPUT ON;
--PROCEDIMIENTO ALMACENADO PARA EFECTUAR CALCULOS DE LOS PAGOS

CREATE OR REPLACE PROCEDURE sp_calcular_pagos
(p_fecha DATE, p_dolar NUMBER)
IS

    CURSOR cr_huespedes IS
        SELECT h.id_huesped,
               h.appat_huesped || ' ' || h.apmat_huesped || ' ' || h.nom_huesped as NOMBRE,    
               r.estadia,
               sum(nvl(hb.valor_habitacion, 0)) * p_dolar as valor_habitacion,
               sum(nvl(hb.valor_minibar, 0)) * p_dolar as valor_minibar,
               sum(case 
                   when hb.tipo_habitacion = 'S' then 1
                   when hb.tipo_habitacion = 'D' then 2
                   when hb.tipo_habitacion = 'T' then 3
                   when hb.tipo_habitacion = 'C' then 4
                   else 0
               end) * 35000 as valor_tipo_habitacion,
               (r.ingreso + r.estadia) as fecha_salida,
               sum(nvl(tc.monto_consumos,0)* p_dolar) as consumo_total,
               sum(nvl(tc.monto_consumos,0) * nvl(tcs.pct,0)) * p_dolar as descuento_consumo
        FROM huesped h
        LEFT JOIN total_consumos tc
            ON (tc.id_huesped = h.id_huesped)
        left JOIN reserva r
            ON (h.id_huesped = r.id_huesped)
        left JOIN detalle_reserva dr
            ON (r.id_reserva = dr.id_reserva)
        left JOIN habitacion hb
            ON (dr.id_habitacion = hb.id_habitacion)
        LEFT JOIN tramos_consumos tcs
            ON (tc.monto_consumos BETWEEN tcs.vmin_tramo AND tcs.vmax_tramo)
        WHERE (r.ingreso + r.estadia)= p_fecha
        group by h.id_huesped, h.appat_huesped, h.apmat_huesped, h.nom_huesped, r.estadia, r.ingreso;
 
v_cant_huesped NUMBER; 
v_valor_por_huesped NUMBER;
v_alojamiento NUMBER;
v_subtotal NUMBER;
v_descuento NUMBER;
v_total_pago NUMBER;
v_descuento_consumo_total NUMBER;
v_nombre_agencia agencia.nom_agencia%TYPE;
v_total_tours NUMBER;

BEGIN

EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_diario_huespedes'; 
EXECUTE IMMEDIATE 'TRUNCATE TABLE reg_errores'; 
    
    FOR reg_detalle IN cr_huespedes LOOP
    
    
    -- variable con valor de la habitacion segun tipo
    v_valor_por_huesped := reg_detalle.valor_tipo_habitacion;
    
    -- variable que almacena el valor total del alojamiento o estadia valor habitacion + minibar por dia
    v_alojamiento := (reg_detalle.valor_habitacion + reg_detalle.valor_minibar)* reg_detalle.estadia;
    
    --variable que almacena el valor de subtotal que corresponde al monto acumulado entre alojamiento +  consumo + el valor por persona
    v_subtotal := (v_alojamiento + reg_detalle.consumo_total + v_valor_por_huesped);
    
    -- variable que almacena el valor de descuento al consumo total
    v_descuento_consumo_total := reg_detalle.descuento_consumo;
    
    v_nombre_agencia := fn_agencia(reg_detalle.id_huesped);
    
    IF v_nombre_agencia = 'VIAJES ALBERTI' THEN 
        v_descuento := v_subtotal * 0.12;
    ELSE
        v_descuento := 0;
    END IF;
    
    --variable que alcemacena el total del pago, osea subtotal - los descuentos
    v_total_pago := v_subtotal - v_descuento - v_descuento_consumo_total;
    
    v_total_tours := pkg_constructores.fn_total_tours(reg_detalle.id_huesped) * p_dolar;
    
    INSERT INTO DETALLE_DIARIO_HUESPEDES 
    VALUES(reg_detalle.id_huesped, reg_detalle.nombre, v_nombre_agencia, round(v_alojamiento), 
    round(reg_detalle.consumo_total), round(v_total_tours), round(v_subtotal), round(v_descuento_consumo_total), round(v_descuento), round(v_total_pago));

    END LOOP;
    
    commit;
    
  END sp_calcular_pagos;
  /
        
  EXECUTE  sp_calcular_pagos('18/08/2021',915);
  
 

