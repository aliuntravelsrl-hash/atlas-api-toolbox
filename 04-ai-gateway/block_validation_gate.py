"""
Módulo Canónico: Gate de Validación Determinista para Ingesta de Bloqueos (Core 2)
Autoridad: Director Soberano Aldo Hilario / Antigravity (ATLAS-TECH)
Tarea: CORE2-003
"""

from datetime import date, datetime
from typing import Dict, Any, List, Optional, Tuple

VALID_CURRENCIES = {"USD", "DOP"}

def validate_block_payload(
    payload: Dict[str, Any],
    existing_hotel_slugs: Optional[set] = None
) -> Tuple[bool, List[str]]:
    """
    Ejecuta el gate de validación estricto sobre un payload candidato a atlas_block_inventory.
    
    Reglas:
    1. Fechas futuras válidas: check_in >= CURRENT_DATE y check_out > check_in.
    2. Tarifas > 0: al menos rate_dbl > 0 o rate_sgl > 0.
    3. Hotel válido: hotel_slug debe existir en el set de hoteles conocidos (hotels_master).
    4. Moneda válida: currency debe ser exactamente USD o DOP.
    
    Retorna:
    (is_valid: bool, errors: List[str])
    """
    errors: List[str] = []
    
    # 1. Validación de fechas
    check_in = payload.get("check_in")
    check_out = payload.get("check_out")
    
    cin_date = None
    cout_date = None
    
    if not check_in:
        errors.append("CHECK_IN_NULL: La fecha de check-in es obligatoria")
    else:
        try:
            if isinstance(check_in, str):
                cin_date = datetime.strptime(check_in.split("T")[0], "%Y-%m-%d").date()
            elif isinstance(check_in, date):
                cin_date = check_in
        except ValueError:
            errors.append(f"CHECK_IN_MALFORMED: Formato inválido para check_in '{check_in}' (esperado YYYY-MM-DD)")
            
    if not check_out:
        errors.append("CHECK_OUT_NULL: La fecha de check-out es obligatoria")
    else:
        try:
            if isinstance(check_out, str):
                cout_date = datetime.strptime(check_out.split("T")[0], "%Y-%m-%d").date()
            elif isinstance(check_out, date):
                cout_date = check_out
        except ValueError:
            errors.append(f"CHECK_OUT_MALFORMED: Formato inválido para check_out '{check_out}' (esperado YYYY-MM-DD)")
            
    if cin_date:
        today = date.today()
        if cin_date < today:
            errors.append(f"CHECK_IN_PAST: check_in ({cin_date}) no puede estar en el pasado (hoy: {today})")
            
    if cin_date and cout_date:
        if cout_date <= cin_date:
            errors.append(f"INVALID_DATE_RANGE: check_out ({cout_date}) debe ser estrictamente posterior a check_in ({cin_date})")

    # 2. Validación de precios
    rate_dbl = payload.get("rate_dbl")
    rate_sgl = payload.get("rate_sgl")
    
    valid_rate = False
    try:
        if rate_dbl is not None and float(rate_dbl) > 0:
            valid_rate = True
    except (ValueError, TypeError):
        pass
        
    try:
        if rate_sgl is not None and float(rate_sgl) > 0:
            valid_rate = True
    except (ValueError, TypeError):
        pass
        
    if not valid_rate:
        errors.append("INVALID_RATES: Se requiere al menos una tarifa (rate_dbl o rate_sgl) mayor a 0")

    # 3. Validación de hotel_slug
    hotel_slug = payload.get("hotel_slug")
    if not hotel_slug or not str(hotel_slug).strip():
        errors.append("HOTEL_SLUG_NULL: El hotel_slug es obligatorio")
    elif existing_hotel_slugs is not None and hotel_slug not in existing_hotel_slugs:
        errors.append(f"HOTEL_NOT_FOUND: El hotel_slug '{hotel_slug}' no existe en hotels_master")

    # 4. Validación de moneda
    currency = payload.get("currency")
    if not currency or str(currency).strip().upper() not in VALID_CURRENCIES:
        errors.append(f"INVALID_CURRENCY: Moneda '{currency}' no válida. Permitidas: {VALID_CURRENCIES}")

    return len(errors) == 0, errors


if __name__ == "__main__":
    # Test suite rápido
    known_hotels = {"barcelo-bavaro-adults-only", "catalonia-bavaro-beach", "secrets-cap-cana"}
    
    # Caso 1: Válido
    valid_item = {
        "hotel_slug": "barcelo-bavaro-adults-only",
        "check_in": "2026-12-01",
        "check_out": "2026-12-05",
        "rate_dbl": 250.0,
        "currency": "USD"
    }
    ok, errs = validate_block_payload(valid_item, known_hotels)
    assert ok, f"Debería ser válido: {errs}"
    print("Test 1 (Válido): PASS")

    # Caso 2: Fecha pasada y moneda inválida
    invalid_item = {
        "hotel_slug": "barcelo-bavaro-adults-only",
        "check_in": "2020-01-01",
        "check_out": "2020-01-02",
        "rate_dbl": 0,
        "currency": "EUR"
    }
    ok, errs = validate_block_payload(invalid_item, known_hotels)
    assert not ok, "Debería ser inválido"
    assert len(errs) >= 3, f"Esperados al menos 3 errores: {errs}"
    print(f"Test 2 (Múltiples errores detectados): PASS -> {errs}")

    # Caso 3: Hotel desconocido
    unknown_hotel = {
        "hotel_slug": "hotel-fantasma-inexistente",
        "check_in": "2026-12-01",
        "check_out": "2026-12-05",
        "rate_dbl": 150.0,
        "currency": "USD"
    }
    ok, errs = validate_block_payload(unknown_hotel, known_hotels)
    assert not ok and any("HOTEL_NOT_FOUND" in e for e in errs)
    print("Test 3 (Hotel desconocido rechazado): PASS")
    
    print("TODOS LOS TESTS DEL GATE PASARON EXITOSAMENTE.")
