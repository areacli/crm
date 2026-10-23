<?php

namespace App\Access;

use RuntimeException;

/** Alteração de acesso recusada por uma regra (R35, R41, PD6, PD7); a mensagem vai para a tela. */
final class AccessRefused extends RuntimeException {}
