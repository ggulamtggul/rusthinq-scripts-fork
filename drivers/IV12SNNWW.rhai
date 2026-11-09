// LG robot vacuum IV12SNNWW (코드제로 로보킹 AI 올인원, ThinQ device type 501, "RK"
// platform): a JSON-protocol ThinQ2 appliance. Reports arrive as CLIP device packets
// whose AA..BB frame carries JSON - a delta under "mon" ({"mon":{"BATT_P":"88"}}) or,
// right after connecting, the full monitoring object. Controls go out as CLIP
// "rkControl" packets {Cmd:"Control", CmdOpt:"Set", Value:...}.
//
// Sources (2026-11-06):
//   - Wire captures on the real appliance (2026-11-05/06) for every control shape.
//   - The device's official app assets from the LG ThinQ service (modelJson, Korean
//     language pack, app module): every label below is the app's own wording, every
//     control Value follows modelJson ControlWifi, and the "allowed in which state"
//     rules follow the app's STATE_CATEGORY switch (which buttons it disables).
//
// Value shapes (captured, and matching ControlWifi): action commands are plain strings
// ("CLEAN_START"); enum settings are objects ({"SUCTION_LEVEL":"STRONG"}; water and
// volume carry their WATER_SUPPLY_ / VOLUME_ prefix); boolean settings are a JSON
// string ("{\"LIGHT\":\"false\"}"). Every control carries clientId and messageId -
// the appliance ignores a Set without them (verified live 2026-11-06).
//
// Map data (RT_MAP / RT_POSE / FLOORMAP / VW) and, while docked, most state travel in
// publishes outside CLIP; the daemon relays those to LG and this driver never sees them.
import "il_common" as il;

// ---- official wording (modelJson Value + language pack) -------------------------------

fn states() {
    #{ "STANDBY": "대기 중", "PAUSE": "일시 정지", "PAUSE_EDGE": "일시정지 중",
       "PAUSE_SPIRAL": "일시정지 중", "PAUSE_ZIGZAG": "일시정지 중", "PAUSE_SELECT": "일시정지 중",
       "PAUSE_LEARNING": "일시 정지", "PAUSE_SELECT_GOZONE": "일시 정지", "HOMING_PAUSE": "일시정지 중",
       "BACKMOVING_JOY": "준비 중", "BACKMOVING_INIT": "준비 중", "MONITORING": "준비 중",
       "INITAILIZING": "준비 중", "RECOVERY_WORKING": "준비 중",
       "CHARGING": "충전 중", "FINISHED_CHARGING": "충전 완료",
       "HOMING": "충전대로 이동 중", "HOMING_LEARNING": "충전대로 이동 중", "DOCKING": "충전대로 이동 중",
       "RECOVERY_HOMING": "충전대로 이동 중",
       "WORKING": "청소 중", "CLEAN_EDGE": "꼼꼼 청소 중", "CLEAN_SPIRAL": "집중청소 중",
       "CLEAN_SELECT": "선택한 방 청소 중", "CLEAN_SPECIFIED": "선택한 구역 청소 중",
       "CLEAN_SELECT_GOZONE": "선택한 구역 청소 중", "CLEAN_ZIGZAG": "퀵 청소 중",
       "CLEAN_LEARNING": "새 도면 그리는 중", "CLEAN_MYSPOT": "구역 청소 중",
       "DIAGNOSIS": "스마트 진단 중", "MONITORING_POSITIONING": "홈가드 위치 지정 중",
       "MONITORING_MOVING": "지정된 위치로 이동 중", "MONITORING_DETECTING": "홈가드 중",
       "SETDATE": "리모컨 사용 중", "MACROSECTOR": "리모컨 사용 중", "RESERVATION": "리모컨 사용 중",
       "SLEEP": "절전 모드 실행 중", "WATER_REMOVAL": "잔수 제거 중", "MYSPOT_RECORDING": "구역 녹화 중",
       "STATION": "먼지통 비우는 중", "STATION_MOP": "물걸레 세척 중", "STATION_DRY": "물걸레 건조 중",
       "REPOSITIONING": "위치 확인 중", "WATER_INJECTION": "물 채우는 중" }
}

fn state_options() {
    ["대기 중", "청소 중", "퀵 청소 중", "꼼꼼 청소 중", "집중청소 중", "선택한 방 청소 중",
     "선택한 구역 청소 중", "구역 청소 중", "새 도면 그리는 중", "일시 정지", "일시정지 중", "준비 중",
     "충전대로 이동 중", "충전 중", "충전 완료", "먼지통 비우는 중", "물걸레 세척 중", "물걸레 건조 중",
     "물 채우는 중", "잔수 제거 중", "절전 모드 실행 중", "스마트 진단 중", "위치 확인 중",
     "리모컨 사용 중", "홈가드 위치 지정 중", "지정된 위치로 이동 중", "홈가드 중", "구역 녹화 중"]
}

// The app's STATE_CATEGORY for each raw state (its getRobotStateInfo switch).
fn categories() {
    #{ "STANDBY": "standby",
       "BACKMOVING_JOY": "prepare", "BACKMOVING_INIT": "prepare", "MONITORING": "prepare",
       "INITAILIZING": "prepare", "REPOSITIONING": "prepare",
       "MONITORING_POSITIONING": "homeguard", "MONITORING_MOVING": "homeguard",
       "MONITORING_DETECTING": "homeguard",
       "RECOVERY_WORKING": "cleaning", "WORKING": "cleaning", "CLEAN_SELECT": "cleaning",
       "CLEAN_SPECIFIED": "cleaning", "CLEAN_SPIRAL": "cleaning", "CLEAN_ZIGZAG": "cleaning",
       "CLEAN_EDGE": "cleaning", "CLEAN_LEARNING": "cleaning", "CLEAN_SELECT_GOZONE": "cleaning",
       "CLEAN_MYSPOT": "cleaning", "MYSPOT_RECORDING": "cleaning",
       "PAUSE": "pause", "PAUSE_LEARNING": "pause", "PAUSE_SELECT_GOZONE": "pause",
       "PAUSE_EDGE": "pause", "PAUSE_SPIRAL": "pause", "PAUSE_ZIGZAG": "pause",
       "PAUSE_SELECT": "pause", "HOMING_PAUSE": "pause",
       "CHARGING": "charging", "FINISHED_CHARGING": "charging",
       "HOMING": "homing", "DOCKING": "homing", "RECOVERY_HOMING": "homing", "HOMING_LEARNING": "homing",
       "DIAGNOSIS": "diagnosis", "SETDATE": "remote", "MACROSECTOR": "remote", "RESERVATION": "remote",
       "SLEEP": "sleep", "WATER_REMOVAL": "water_removal", "STATION": "station",
       "STATION_MOP": "station_mop", "STATION_DRY": "station_dry", "WATER_INJECTION": "water_injection" }
}

// Which control group the app leaves enabled in each category (disabledCleaningButton,
// disabledChargeButton, disabledCleanModeButton, disabledSimpleControlButton,
// listDimmed); "error" is the app's STATE_ERROR (an emergency is active).
fn allowed() {
    #{ clean: ["standby", "cleaning", "pause", "charging", "station_dry"],
       pause: ["cleaning", "homing"],
       charge: ["standby", "pause", "homing"],
       mode: ["standby", "pause", "charging"],
       simple: ["standby", "cleaning", "pause", "charging", "homing"],
       settings: ["standby", "cleaning", "pause", "charging", "homing", "station", "station_mop",
                  "station_dry", "water_injection", "error"],
       station: ["charging"],
       dry_stop: ["station_dry"],
       find: ["standby", "cleaning", "pause", "charging", "homing", "station", "station_mop",
              "station_dry", "water_injection", "error", "prepare"] }
}

fn prop_group() {
    #{ clean_start: "clean", clean_stop: "clean", spot_clean: "clean", pause: "pause",
       homing: "charge", clean_type: "mode", clean_distance: "mode",
       suction: "simple", water_supply: "simple", smart_turbo: "simple",
       volume: "settings", light_mode: "settings", button_lock: "settings",
       reclean_mode: "settings", ai_detection: "settings",
       station_empty: "station", mop_wash: "station", mop_dry: "station",
       mop_dry_stop: "dry_stop", find_robot: "find" }
}

fn emergencies() {
    #{ "E_BUMPER_STUCK": "범퍼가 눌려있습니다. 제품을 확인해주세요.",
       "E_WHEEL_STUCK": "바퀴에 문제가 생겨 이동할 수 없습니다. 바퀴의 이물질을 제거해주세요.",
       "E_MOP_STUCK": "걸레판 회전에 문제가 생겼습니다.",
       "E_SIDEBRUSH_STUCK": "회전솔에 문제가 생겨 이동할 수 없습니다. 측면 회전솔의 이물질을 제거해주세요.",
       "E_ROLLBRUSH_STUCK": "바닥면 회전솔에 문제가 생겨 이동할 수 없습니다. 회전솔의 이물질을 제거해주세요.",
       "E_ROBOT_STUCK": "청소를 계속할 수 없습니다. 청소 로봇 주변 환경을 확인해주세요.",
       "E_ROBOT_LIFT": "바퀴가 바닥에 닿지 않았습니다. 제품을 평평한 바닥으로 옮겨 주세요.",
       "E_WHEEL_LIFT": "바퀴가 바닥에 닿지 않았습니다. 제품을 평평한 바닥으로 옮겨 주세요.",
       "E_BATTERY_LOW": "제품을 충전대로 옮겨 충전해주세요.",
       "E_MAGNETIC_DISRUPT": "청소를 계속할 수 없습니다. 청소 로봇 주변 환경을 확인해주세요.",
       "E_IRSENSOR_BLOCK": "장애물 감지 센서창에 문제가 생겨 이동할 수 없습니다. 장애물 감지 센서창을 닦아주세요.",
       "E_WALLSENSORR_BLOCK": "장애물 감지 센서창에 문제가 생겨 이동할 수 없습니다. 장애물 감지 센서창을 닦아주세요.",
       "E_ROBOT_TILT": "청소를 계속할 수 없습니다. 제품을 평평한 바닥으로 옮겨 주세요.",
       "E_DUSTBIN_OFF": "먼지통이 없어 청소를 시작할 수 없어요. 먼지통을 장착해주세요.",
       "E_RESTRICTED_NEAR": "제품이 청소 금지 영역 안에 있어 청소할 수 없어요. 청소 로봇의 위치를 확인해주세요.",
       "E_LASERCOVER_STUCK": "라이다 센서 커버가 눌려 이동할 수 없습니다. 상부 라이다 센서 커버를 확인해주세요.",
       "E_LASERSENSOR_STUCK": "라이다 센서에 문제가 생겨 이동할 수 없습니다. 라이다 센서 주변의 이물질을 제거해주세요.",
       "E_LASERSENSOR_BLOCK": "라이다 센서에 문제가 생겨 이동할 수 없습니다. 라이다 센서 주변의 이물질을 제거해주세요.",
       "E_BATTERY_ERROR": "배터리에 문제가 생겼습니다.",
       "E_SUCTIONFAN_ERROR": "흡입모터에 문제가 생겼습니다.",
       "E_WATERPUMP_ERROR": "펌프 모터에 문제가 생겼습니다.",
       "E_CLIFFSENSOR_BLOCK": "낭떠러지 센서에 문제가 생겨 이동할 수 없습니다. 낭떠러지 센서를 닦아주세요.",
       "E_WHEEL_ERROR": "바퀴 모터에 문제가 생겼습니다.",
       "E_SIDEBRUSH_ERROR": "측면 회전솔 모터에 문제가 생겼습니다.",
       "E_ROLLBRUSH_ERROR": "회전솔 모터에 문제가 생겼습니다.",
       "E_WALLSENSOR_ERROR": "우측 벽면 감지 센서에 문제가 생겼습니다.",
       "E_3DSENSOR_ERROR": "카메라 센서에 문제가 생겼습니다.",
       "E_LASERSENSOR_ERROR": "라이다 센서에 문제가 생겼습니다.",
       "E_CLIFFSENSOR_ERROR": "낭떠러지 센서에 문제가 생겼습니다.",
       "E_OBSTSENSOR_ERROR": "장애물 감지 센서에 문제가 생겼습니다.",
       "E_WALLSENSOR_BLOCK": "우측 벽면 감지 센서에 문제가 생겨 이동할 수 없습니다. 우측 벽면 감지 센서창을 닦아주세요.",
       "E_3DSENSOR_BLOCK": "카메라 센서에 문제가 생겨 이동할 수 없습니다. 카메라 센서창을 닦아주세요.",
       "E_MOP_ERROR": "걸레판 모터에 문제가 생겼습니다.",
       "E_MOP_DETACHED": "물걸레가 떨어져 청소가 멈췄어요. 물걸레를 잘 부착해주세요.",
       "E_TEMP_ERROR": "청소 로봇 온도에 문제가 생겼습니다.",
       "E_SYSTEM_ERROR": "시스템에 문제가 생겼습니다." }
}

fn clean_modes() {
    #{ "ZZ": "지그재그", "SB": "꼼꼼청소", "SPOT": "집중청소", "MACRO": "전체 청소", "EDGE": "꼼꼼청소",
       "SELECT": "선택 영역", "MY": "내 영역 청소", "GYRO": "자이로 청소", "DEEP": "꼼꼼 청소",
       "AREA": "영역 청소", "CUSTOM": "맞춤청소" }
}

fn suction_levels() { #{ "NONE": "없음", "QUIET": "약", "STANDARD": "중", "STRONG": "강", "MAX": "터보" } }
fn suction_wires() { #{ "약": "QUIET", "중": "STANDARD", "강": "STRONG", "터보": "MAX" } }
fn water_levels() { #{ "DRY": "물기 없이", "LOW": "적게", "LOW1": "보통", "HIGH": "많이" } }
fn water_wires() { #{ "물기 없이": "DRY", "적게": "LOW", "보통": "LOW1", "많이": "HIGH" } }
fn volume_levels() { #{ "MUTE": "음소거", "LOW": "작게", "MEDIUM": "보통", "HIGH": "크게" } }
fn volume_wires() { #{ "음소거": "MUTE", "작게": "LOW", "보통": "MEDIUM", "크게": "HIGH" } }
fn clean_types() { #{ "ALL": "먼지 흡입 + 물걸레", "SUCTION": "먼지 흡입", "MOP": "물걸레" } }
fn clean_type_wires() { #{ "먼지 흡입 + 물걸레": "ALL", "먼지 흡입": "SUCTION", "물걸레": "MOP" } }
fn dist_levels() { #{ "QUICK": "넓게", "NORMAL": "기본", "DEEP": "좁게", "DEEPSLOW": "꼼꼼+" } }
fn dist_wires() { #{ "넓게": "QUICK", "기본": "NORMAL", "좁게": "DEEP", "꼼꼼+": "DEEPSLOW" } }
fn station_modes() { #{ "AUTO": "자동", "MANUAL": "수동" } }
fn update_states() {
    #{ "IDLE": "대기", "DOWNLOADING": "다운로드 중", "COMPLETE": "완료",
       "MD5_FAILED": "검증 실패", "DOWNLOAD_FAILED": "다운로드 실패" }
}

// ---- descriptor ---------------------------------------------------------------------

fn descriptor(ctx) {
    let props = #{
        available: #{ type: "binary", role: "available" },
        state: #{ type: "select", role: "state", options: state_options(), label: "현재 상태" },
        state_raw: #{ type: "text", category: "diagnostic", label: "상태 (원본)" },
        error: #{ type: "binary", class: "problem", label: "오류 있음" },
        error_code: #{ type: "text", category: "diagnostic", label: "오류 코드 (원본)" },
        error_message: #{ type: "text", label: "오류 내용" },
        last_reject: #{ type: "text", category: "diagnostic", label: "마지막 거절 사유" },
        battery: #{ type: "number", unit: "%", min: 0, max: 100, label: "배터리" },
        clean_mode: #{ type: "select", label: "청소 모드",
                       options: ["지그재그", "꼼꼼청소", "집중청소", "전체 청소", "선택 영역", "내 영역 청소",
                                 "자이로 청소", "꼼꼼 청소", "영역 청소", "맞춤청소"] },
        suction: #{ type: "select", label: "흡입 세기", rw: true, options: ["약", "중", "강", "터보", "없음"] },
        water_supply: #{ type: "select", label: "물공급량", rw: true, options: ["물기 없이", "적게", "보통", "많이"] },
        volume: #{ type: "select", category: "config", label: "제품 볼륨", rw: true,
                   options: ["음소거", "작게", "보통", "크게"] },
        clean_type: #{ type: "select", label: "청소 방식", rw: true, options: ["먼지 흡입 + 물걸레", "먼지 흡입", "물걸레"] },
        clean_distance: #{ type: "select", label: "청소 간격", rw: true, options: ["넓게", "기본", "좁게", "꼼꼼+"] },
        smart_turbo: #{ type: "binary", label: "스마트 터보", rw: true },
        sleep_mode: #{ type: "binary", category: "config", label: "절전 모드" },
        button_lock: #{ type: "binary", category: "config", label: "제품 버튼 잠금", rw: true },
        reclean_mode: #{ type: "binary", category: "config", label: "자동으로 이어서 청소하기", rw: true },
        light_mode: #{ type: "binary", category: "config", label: "조명", rw: true },
        ai_detection: #{ type: "binary", category: "config", label: "AI 장애물 회피", rw: true },
        carpet_avoid: #{ type: "text", category: "diagnostic", label: "카펫 청소 방식 (원본)" },
        station_mode: #{ type: "select", category: "config", label: "자동 먼지 비움 설정", options: ["자동", "수동"] },
        clean_time: #{ type: "number", class: "duration", unit: "min", label: "청소 시간" },
        clean_where: #{ type: "number", category: "diagnostic", label: "청소 위치" },
        maint_main_brush: #{ type: "number", category: "diagnostic", label: "메인 브러시 사용량" },
        maint_side_brush: #{ type: "number", category: "diagnostic", label: "사이드 브러시 사용량" },
        maint_filter: #{ type: "number", category: "diagnostic", label: "필터 사용량" },
        maint_mop: #{ type: "number", category: "diagnostic", label: "물걸레 사용량" },
        maint_dust_bag: #{ type: "number", category: "diagnostic", label: "먼지 봉투 사용량" },
        update: #{ type: "select", category: "diagnostic", label: "펌웨어 업데이트",
                   options: ["대기", "다운로드 중", "완료", "검증 실패", "다운로드 실패"] },
        update_progress: #{ type: "number", category: "diagnostic", unit: "%", label: "업데이트 진행률" },
        product_version: #{ type: "text", category: "diagnostic", label: "제품 버전" },
        language: #{ type: "text", category: "diagnostic", label: "언어" },
        robot_event: #{ type: "text", category: "diagnostic", label: "로봇 이벤트" },
        clean_order: #{ type: "text", category: "diagnostic", label: "청소 순서 (JSON)" },
        reservation: #{ type: "text", category: "diagnostic", label: "예약 (JSON)" },
        do_not_disturb: #{ type: "text", category: "diagnostic", label: "방해 금지 (JSON)" },
        clean_start: #{ type: "trigger", label: "청소 시작" },
        pause: #{ type: "trigger", label: "청소 일시정지" },
        clean_stop: #{ type: "trigger", label: "청소 정지" },
        homing: #{ type: "trigger", label: "충전 복귀" },
        spot_clean: #{ type: "trigger", label: "집중청소 시작" },
        station_empty: #{ type: "trigger", label: "먼지 비우기" },
        mop_wash: #{ type: "trigger", label: "물걸레 바로 세척" },
        mop_dry: #{ type: "trigger", label: "물걸레 바로 건조" },
        mop_dry_stop: #{ type: "trigger", label: "물걸레 건조 종료" },
        find_robot: #{ type: "trigger", label: "청소 로봇 위치 찾기" }
    };
    json_stringify(#{ il: 0, kind: "vacuum", label: "로봇청소기", vendor: "LG",
                      model: ctx.model_id(), props: props })
}

fn publish_config(ctx) { il::publish_il(ctx, descriptor(ctx)); }

// ---- kept state -----------------------------------------------------------------------

// The appliance pushes only deltas and no status query is known, so a hot reload (which
// re-announces the entities) would leave them empty until each value next changes.
// Every published value is kept in driver state and republished here; nothing is sent.
fn start(ctx) {
    let keys = ctx.state_get("kept3_keys");
    if keys == () { return; }
    for k in keys.split(",") {
        if k == "" { continue; }
        let v = ctx.state_get("kept3_" + k);
        if v != () { il::publish_property(ctx, k, v); }
    }
}

fn pubp(ctx, prop, value) {
    il::publish_property(ctx, prop, value);
    ctx.state_set("kept3_" + prop, value);
    let keys = ctx.state_get("kept3_keys");
    if keys == () { keys = ""; }
    if !("," + keys + ",").contains("," + prop + ",") {
        ctx.state_set("kept3_keys", if keys == "" { prop } else { keys + "," + prop });
    }
}

fn on_drop(ctx) { il::publish_property(ctx, "available", "false"); }

// ---- payload walking ------------------------------------------------------------------

fn get2(s, key) {
    if type_of(s) != "map" { return (); }
    if s.contains(key) { return s[key]; }
    for v in s.values() {
        if type_of(v) == "map" && v.contains(key) { return v[key]; }
    }
    ()
}

fn num_text(v) {
    if type_of(v) == "i64" { return v.to_string(); }
    if type_of(v) == "f64" {
        if v == v.floor() { return v.to_int().to_string(); }
        return v.to_string();
    }
    if type_of(v) == "string" {
        let n = (); try { n = v.parse_float(); } catch {}
        if n != () { return num_text(n); }
    }
    ()
}

// MAINT_* values arrive as "used|total" strings; publish the used figure.
fn maint_text(v) {
    if type_of(v) == "string" && v.contains("|") { return num_text(v.split("|")[0]); }
    num_text(v)
}

fn bool_text(v) {
    if type_of(v) == "bool" { return v.to_string(); }
    if type_of(v) == "i64" { return if v != 0 { "true" } else { "false" }; }
    if type_of(v) == "string" {
        let t = v.to_lower();
        if ["true", "on", "1"].contains(t) { return "true"; }
        if ["false", "off", "0"].contains(t) { return "false"; }
    }
    ()
}

fn pub_num(ctx, s, key, prop) { let v = num_text(get2(s, key)); if v != () { pubp(ctx, prop, v); } }
fn pub_maint(ctx, s, key, prop) { let v = maint_text(get2(s, key)); if v != () { pubp(ctx, prop, v); } }
fn pub_bool(ctx, s, key, prop) { let v = bool_text(get2(s, key)); if v != () { pubp(ctx, prop, v); } }

fn pub_bool_any(ctx, s, keys, prop) {
    for key in keys {
        let v = bool_text(get2(s, key));
        if v != () { pubp(ctx, prop, v); return; }
    }
}

// Enum reports may carry the wire prefix (WATER_SUPPLY_LOW1, VOLUME_HIGH); strip it.
fn pub_enum(ctx, s, key, prop, table, prefix) {
    let raw = get2(s, key);
    if type_of(raw) != "string" { return; }
    if prefix != "" && raw.starts_with(prefix) { raw = raw.sub_string(prefix.len()); }
    let name = table[raw];
    if name != () { pubp(ctx, prop, name); }
}

fn pub_raw(ctx, s, key, prop) {
    let v = get2(s, key);
    if v == () { return; }
    if type_of(v) == "string" { pubp(ctx, prop, v); }
    else if type_of(v) == "array" {
        let w = json_stringify(#{ v: v });
        pubp(ctx, prop, w[5..w.len() - 1]);
    }
    else { pubp(ctx, prop, json_stringify(v)); }
}

fn on_data(ctx, data) {
    let start = -1;
    for i in 0..data.len() { if data[i] == 123 { start = i; break; } }
    if start < 0 { return; }
    ctx.state_set("rx_seed", crc16(data));
    let end = -1;
    let idx = data.len() - 1;
    while idx > start { if data[idx] == 125 { end = idx; break; } idx -= 1; }
    if end < 0 { return; }
    let text = ""; try { text = bytes_utf8(data.extract(start, end - start + 1)); } catch { return; }
    let s = (); try { s = json_parse(text); } catch { return; }
    if type_of(s) != "map" { return; }
    if s.contains("controlResult") { return; }
    let body = if type_of(s["mon"]) == "map" { s["mon"] } else { s };
    let known = false;
    for k in ["ROBOT_STATE", "BATT_P", "MODE", "SUCTION_LEVEL", "WATERSUPPLY_LEVEL",
              "VOLUME_LEVEL", "CLEAN_TYPE", "ZZ_DIST", "STATION_SET", "SMART_TURBO", "BUTTON_LOCK",
              "RECLEAN", "TOGGLE_RECLEAN", "LIGHT", "AI_DETECTION", "MAINT_FILTER", "UPDATE", "EMERGENCY",
              "UTC_SLEEPMODE", "SLEEP_MODE", "CARPET_AVOID", "CLEAN_TIME", "CLEAN_WHERE",
              "MAINT_MAINBRUSH", "MAINT_SIDEBRUSH", "MAINT_MOP", "MAINT_DUSTBAG", "VERSION",
              "LANGUAGE", "ROBOT_EVENT", "CLEAN_ORDER", "CLEANING_RSV", "DND_INFO"] {
        if get2(body, k) != () { known = true; break; }
    }
    if !known { return; }
    pubp(ctx, "available", "true");

    let state_holder = get2(body, "ROBOT_STATE");
    let emergency = get2(body, "EMERGENCY");
    let state_raw = ();
    if type_of(state_holder) == "string" { state_raw = state_holder; }
    else if type_of(state_holder) == "map" {
        if type_of(state_holder["ROBOT_STATE"]) == "string" { state_raw = state_holder["ROBOT_STATE"]; }
        if emergency == () && state_holder.contains("EMERGENCY") { emergency = state_holder["EMERGENCY"]; }
    }
    if state_raw != () {
        ctx.state_set("raw_state", state_raw);
        pubp(ctx, "state_raw", state_raw);
        let name = states()[state_raw];
        if name != () { pubp(ctx, "state", name); }
    }
    if type_of(emergency) == "string" {
        ctx.state_set("emergency", emergency);
        pubp(ctx, "error_code", emergency);
        pubp(ctx, "error", if emergency == "NONE" { "false" } else { "true" });
        let msg = emergencies()[emergency];
        pubp(ctx, "error_message", if emergency == "NONE" { "없음" } else if msg != () { msg } else { emergency });
    }

    pub_num(ctx, body, "BATT_P", "battery");
    pub_enum(ctx, body, "MODE", "clean_mode", clean_modes(), "");
    pub_enum(ctx, body, "SUCTION_LEVEL", "suction", suction_levels(), "");
    pub_enum(ctx, body, "WATERSUPPLY_LEVEL", "water_supply", water_levels(), "WATER_SUPPLY_");
    pub_enum(ctx, body, "VOLUME_LEVEL", "volume", volume_levels(), "VOLUME_");
    pub_enum(ctx, body, "CLEAN_TYPE", "clean_type", clean_types(), "");
    pub_enum(ctx, body, "ZZ_DIST", "clean_distance", dist_levels(), "");
    pub_enum(ctx, body, "STATION_SET", "station_mode", station_modes(), "");
    pub_bool(ctx, body, "SMART_TURBO", "smart_turbo");
    pub_bool_any(ctx, body, ["UTC_SLEEPMODE", "SLEEP_MODE"], "sleep_mode");
    pub_bool(ctx, body, "BUTTON_LOCK", "button_lock");
    // The report carries both RECLEAN and TOGGLE_RECLEAN; the app's setting is
    // TOGGLE_RECLEAN (ControlWifi SetToggleReclean, cross-checked with the cloud).
    pub_bool_any(ctx, body, ["TOGGLE_RECLEAN", "RECLEAN"], "reclean_mode");
    pub_bool(ctx, body, "LIGHT", "light_mode");
    pub_bool(ctx, body, "AI_DETECTION", "ai_detection");
    pub_raw(ctx, body, "CARPET_AVOID", "carpet_avoid");
    pub_num(ctx, body, "CLEAN_TIME", "clean_time");
    pub_num(ctx, body, "CLEAN_WHERE", "clean_where");
    pub_maint(ctx, body, "MAINT_MAINBRUSH", "maint_main_brush");
    pub_maint(ctx, body, "MAINT_SIDEBRUSH", "maint_side_brush");
    pub_maint(ctx, body, "MAINT_FILTER", "maint_filter");
    pub_maint(ctx, body, "MAINT_MOP", "maint_mop");
    pub_maint(ctx, body, "MAINT_DUSTBAG", "maint_dust_bag");
    pub_raw(ctx, body, "VERSION", "product_version");
    pub_raw(ctx, body, "LANGUAGE", "language");
    pub_raw(ctx, body, "ROBOT_EVENT", "robot_event");
    pub_raw(ctx, body, "CLEAN_ORDER", "clean_order");
    pub_raw(ctx, body, "CLEANING_RSV", "reservation");
    pub_raw(ctx, body, "DND_INFO", "do_not_disturb");

    let upd = get2(body, "UPDATE");
    if type_of(upd) == "string" {
        let name = update_states()[upd];
        if name != () { pubp(ctx, "update", name); }
    } else if type_of(upd) == "map" {
        if type_of(upd["UPDATE"]) == "string" {
            let name = update_states()[upd["UPDATE"]];
            if name != () { pubp(ctx, "update", name); }
        }
        let p = num_text(upd["DownloadProgress"]);
        if p != () { pubp(ctx, "update_progress", p); }
    }
}

// ---- state gating (the app's disabled-button rules) ------------------------------------

fn current_category(ctx) {
    let e = ctx.state_get("emergency");
    if e != () && e != "NONE" { return "error"; }
    let raw = ctx.state_get("raw_state");
    if raw == () { return (); }
    categories()[raw]
}

// Returns a refusal message, or () when the control is allowed. An unknown state (no
// report since attach) allows everything rather than blocking blindly.
fn refusal(ctx, prop) {
    let group = prop_group()[prop];
    if group == () { return (); }
    let cat = current_category(ctx);
    if cat == () { return (); }
    // Asleep the app disables its buttons behind "절전 모드 해제", but the robot itself
    // takes a command while asleep, applies it and wakes (verified live 2026-11-07:
    // CLEAN_TYPE sent in SLEEP -> mon CLEAN_TYPE, controlResult 0000, then
    // FINISHED_CHARGING). So nothing is refused for being asleep.
    if cat == "sleep" { return (); }
    let raw = ctx.state_get("raw_state");
    // App rule: focus (spot) cleaning cannot start while charging.
    if prop == "spot_clean" && cat == "charging" { return "충전 중에는 집중청소를 할 수 없어요."; }
    if allowed()[group].contains(cat) { return (); }
    let label = if cat == "error" { "오류" } else { states()[raw] };
    if label == () { label = raw; }
    if group == "station" { return "청소 로봇이 충전대에 있을 때만 사용할 수 있어요. (현재: " + label + ")"; }
    if group == "mode" && cat == "cleaning" { return "청소 중에는 설정할 수 없어요. 청소가 끝난 뒤 다시 시도해주세요."; }
    "지금은 사용할 수 없어요. (현재: " + label + ")"
}

// ---- writes ---------------------------------------------------------------------------

fn client_id() { "79b237256c9129df9f43207e279b4cf240926a6f3734d960740cd2b3846f748a" }

fn message_id(ctx) {
    // No clock in the engine: a per-driver counter mixed with the CRC of the last report
    // received keeps ids unique across daemon restarts in practice.
    let n = ctx.state_get("msg_seq");
    if n == () { n = 0; }
    n += 1;
    ctx.state_set("msg_seq", n);
    let seed = ctx.state_get("rx_seed");
    if seed == () { seed = 0; }
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let v = seed * 1000003 + n;
    let id = "rhq";
    for i in 0..19 {
        id += alphabet.sub_string(v % 62, 1);
        v = v / 62 + (i + 1) * 7919 + n;
    }
    id
}

fn rk_set(ctx, value) {
    ctx.send_clip("rkControl", 0, json_stringify(#{ Cmd: "Control", CmdOpt: "Set", Value: value,
                                                    clientId: client_id(), messageId: message_id(ctx) }));
}

fn rk_set_bool(ctx, key, value) {
    let inner = #{}; inner[key] = value;
    rk_set(ctx, json_stringify(inner));
}

fn on_set_property(ctx, prop, value) {
    let value = il::validate(ctx, prop, value);
    if value == () { return; }
    let why = refusal(ctx, prop);
    if why != () {
        il::publish_property(ctx, "last_reject", why);
        il::reject(ctx, prop, "not_now", why);
        return;
    }
    switch prop {
        "clean_start" => rk_set(ctx, "CLEAN_START"),
        "pause" => rk_set(ctx, "PAUSE"),
        "clean_stop" => rk_set(ctx, "CLEAN_STOP"),
        "homing" => rk_set(ctx, "HOMING"),
        "spot_clean" => rk_set(ctx, "CLEAN_START_SPOT"),
        "station_empty" => rk_set(ctx, "STATION_START"),
        "mop_wash" => rk_set(ctx, "MOPWASH_START"),
        "mop_dry" => rk_set(ctx, "MOPDRY_START"),
        "mop_dry_stop" => rk_set(ctx, "MOPDRY_STOP"),
        "find_robot" => rk_set(ctx, "WHERE_IS_ROBOT"),
        "suction" => {
            let wire = suction_wires()[value];
            if wire == () { il::reject(ctx, prop, "read_only", "없음은 설정할 수 없어요."); return; }
            rk_set(ctx, #{ SUCTION_LEVEL: wire });
        }
        "water_supply" => rk_set(ctx, #{ WATER_SUPPLY_LEVEL: "WATER_SUPPLY_" + water_wires()[value] }),
        "volume" => rk_set(ctx, #{ VOLUME_LEVEL: "VOLUME_" + volume_wires()[value] }),
        "clean_type" => rk_set(ctx, #{ CLEAN_TYPE: clean_type_wires()[value] }),
        "clean_distance" => rk_set(ctx, #{ ZZ_DIST: dist_wires()[value] }),
        "smart_turbo" => rk_set_bool(ctx, "SMART_TURBO", value),
        "button_lock" => rk_set_bool(ctx, "BUTTON_LOCK", value),
        "reclean_mode" => rk_set_bool(ctx, "TOGGLE_RECLEAN", value),
        "light_mode" => rk_set_bool(ctx, "LIGHT", value),
        "ai_detection" => rk_set_bool(ctx, "AI_DETECTION", value),
        _ => il::reject(ctx, prop, "read_only", "read-only property")
    }
}
