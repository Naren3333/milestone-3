#!/bin/sh
set -eu

export MOODLE_DATABASE_TYPE="${MOODLE_DATABASE_TYPE:-mariadb}"
export MOODLE_DATABASE_HOST="${MOODLE_DATABASE_HOST:-moodledb}"
export MOODLE_DATABASE_PORT_NUMBER="${MOODLE_DATABASE_PORT_NUMBER:-3306}"
export MOODLE_DATABASE_NAME="${MOODLE_DATABASE_NAME:-moodle}"
export MOODLE_DATABASE_USER="${MOODLE_DATABASE_USER:-moodle}"
export MOODLE_DATABASE_PASSWORD="${MOODLE_DATABASE_PASSWORD:-moodlepass}"
export MOODLE_DATABASE_PREFIX="${MOODLE_DATABASE_PREFIX:-mdl_}"
export MOODLE_ADMIN_USER="${MOODLE_ADMIN_USER:-admin}"
export MOODLE_ADMIN_PASSWORD="${MOODLE_ADMIN_PASSWORD:-ChangeMe123!}"
export MOODLE_ADMIN_EMAIL="${MOODLE_ADMIN_EMAIL:-admin@example.com}"
export MOODLE_SITE_NAME="${MOODLE_SITE_NAME:-ESMOS Healthcare Compliance Academy}"
export MOODLE_SHORT_NAME="${MOODLE_SHORT_NAME:-ESMOS}"
export MOODLE_DATA_DIR="${MOODLE_DATA_DIR:-/var/moodledata}"
export MOODLE_WWWROOT="${MOODLE_WWWROOT:-http://localhost:8080}"
export MOODLE_REVERSE_PROXY="${MOODLE_REVERSE_PROXY:-0}"

wait_for_database() {
    attempts=0
    until php <<'PHP'
<?php
mysqli_report(MYSQLI_REPORT_OFF);
$db = @new mysqli(
    getenv('MOODLE_DATABASE_HOST'),
    getenv('MOODLE_DATABASE_USER'),
    getenv('MOODLE_DATABASE_PASSWORD'),
    getenv('MOODLE_DATABASE_NAME'),
    (int)(getenv('MOODLE_DATABASE_PORT_NUMBER') ?: 3306)
);
exit($db->connect_errno ? 1 : 0);
PHP
    do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 30 ]; then
            echo "Database did not become ready in time." >&2
            exit 1
        fi
        sleep 5
    done
}

write_config() {
    php <<'PHP'
<?php
$path = '/var/www/html/config.php';
$reverseProxy = getenv('MOODLE_REVERSE_PROXY') === '1';
$config = "<?php\nunset(\$CFG);\n";
$config .= "\$CFG = new stdClass();\n";
$config .= "\$CFG->dbtype = " . var_export(getenv('MOODLE_DATABASE_TYPE') ?: 'mariadb', true) . ";\n";
$config .= "\$CFG->dblibrary = 'native';\n";
$config .= "\$CFG->dbhost = " . var_export(getenv('MOODLE_DATABASE_HOST') ?: 'moodledb', true) . ";\n";
$config .= "\$CFG->dbname = " . var_export(getenv('MOODLE_DATABASE_NAME') ?: 'moodle', true) . ";\n";
$config .= "\$CFG->dbuser = " . var_export(getenv('MOODLE_DATABASE_USER') ?: 'moodle', true) . ";\n";
$config .= "\$CFG->dbpass = " . var_export(getenv('MOODLE_DATABASE_PASSWORD') ?: 'moodlepass', true) . ";\n";
$config .= "\$CFG->prefix = " . var_export(getenv('MOODLE_DATABASE_PREFIX') ?: 'mdl_', true) . ";\n";
$config .= "\$CFG->dboptions = array (\n";
$config .= "  'dbpersist' => 0,\n";
$config .= "  'dbport' => " . var_export(getenv('MOODLE_DATABASE_PORT_NUMBER') ?: '3306', true) . ",\n";
$config .= "  'dbsocket' => '',\n";
$config .= "  'dbcollation' => 'utf8mb4_unicode_ci',\n";
$config .= ");\n";
$config .= "\$CFG->wwwroot = " . var_export(getenv('MOODLE_WWWROOT') ?: 'http://localhost:8080', true) . ";\n";
$config .= "\$CFG->dataroot = " . var_export(getenv('MOODLE_DATA_DIR') ?: '/var/moodledata', true) . ";\n";
$config .= "\$CFG->admin = 'admin';\n";
$config .= "\$CFG->directorypermissions = 02770;\n";
if ($reverseProxy) {
    $config .= "\$CFG->reverseproxy = true;\n";
    $config .= "\$CFG->sslproxy = true;\n";
}
$config .= "require_once(__DIR__ . '/lib/setup.php');\n";
file_put_contents($path, $config);
PHP
    chown www-data:www-data /var/www/html/config.php
}

ensure_runtime_flags() {
    php <<'PHP'
<?php
$path = '/var/www/html/config.php';
if (!file_exists($path)) {
    exit(0);
}
$config = file_get_contents($path);
if ($config === false) {
    fwrite(STDERR, "Unable to read config.php\n");
    exit(1);
}

$wwwroot = getenv('MOODLE_WWWROOT') ?: 'http://localhost:8080';
$dataroot = getenv('MOODLE_DATA_DIR') ?: '/var/moodledata';
$reverseProxy = getenv('MOODLE_REVERSE_PROXY') === '1';

$config = preg_replace("/\\$CFG->wwwroot\\s*=\\s*.*?;\\n/", "\$CFG->wwwroot = " . var_export($wwwroot, true) . ";\n", $config, 1);
$config = preg_replace("/\\$CFG->dataroot\\s*=\\s*.*?;\\n/", "\$CFG->dataroot = " . var_export($dataroot, true) . ";\n", $config, 1);

if ($reverseProxy) {
    if (strpos($config, '$CFG->reverseproxy') === false) {
        $config = str_replace("require_once(__DIR__ . '/lib/setup.php');", "\$CFG->reverseproxy = true;\nrequire_once(__DIR__ . '/lib/setup.php');", $config);
    }
    if (strpos($config, '$CFG->sslproxy') === false) {
        $config = str_replace("require_once(__DIR__ . '/lib/setup.php');", "\$CFG->sslproxy = true;\nrequire_once(__DIR__ . '/lib/setup.php');", $config);
    }
}

file_put_contents($path, $config);
PHP
    chown www-data:www-data /var/www/html/config.php
}

is_installed() {
    php <<'PHP'
<?php
mysqli_report(MYSQLI_REPORT_OFF);
$db = @new mysqli(
    getenv('MOODLE_DATABASE_HOST'),
    getenv('MOODLE_DATABASE_USER'),
    getenv('MOODLE_DATABASE_PASSWORD'),
    getenv('MOODLE_DATABASE_NAME'),
    (int)(getenv('MOODLE_DATABASE_PORT_NUMBER') ?: 3306)
);
if ($db->connect_errno) {
    exit(1);
}
$prefix = $db->real_escape_string((getenv('MOODLE_DATABASE_PREFIX') ?: 'mdl_') . 'config');
$result = $db->query("SHOW TABLES LIKE '{$prefix}'");
exit($result && $result->num_rows > 0 ? 0 : 1);
PHP
}

install_moodle() {
    su -s /bin/sh www-data -c 'php /var/www/html/admin/cli/install.php \
        --lang=en \
        --wwwroot="$MOODLE_WWWROOT" \
        --dataroot="$MOODLE_DATA_DIR" \
        --dbtype="$MOODLE_DATABASE_TYPE" \
        --dbhost="$MOODLE_DATABASE_HOST" \
        --dbport="$MOODLE_DATABASE_PORT_NUMBER" \
        --dbname="$MOODLE_DATABASE_NAME" \
        --dbuser="$MOODLE_DATABASE_USER" \
        --dbpass="$MOODLE_DATABASE_PASSWORD" \
        --prefix="$MOODLE_DATABASE_PREFIX" \
        --fullname="$MOODLE_SITE_NAME" \
        --shortname="$MOODLE_SHORT_NAME" \
        --adminuser="$MOODLE_ADMIN_USER" \
        --adminpass="$MOODLE_ADMIN_PASSWORD" \
        --adminemail="$MOODLE_ADMIN_EMAIL" \
        --non-interactive \
        --agree-license'
}

mkdir -p "$MOODLE_DATA_DIR"
chown -R www-data:www-data "$MOODLE_DATA_DIR"

wait_for_database

if ! is_installed; then
    rm -f /var/www/html/config.php
    install_moodle
elif [ ! -f /var/www/html/config.php ]; then
    write_config
fi

ensure_runtime_flags

exec "$@"
