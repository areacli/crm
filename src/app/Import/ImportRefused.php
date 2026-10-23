<?php

namespace App\Import;

use RuntimeException;

/** O arquivo inteiro é recusado antes da conferência linha a linha (cabeçalho, codificação, tamanho). */
final class ImportRefused extends RuntimeException {}
