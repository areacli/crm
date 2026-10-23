<?php

namespace App\Contacts;

use RuntimeException;

/** Registro, anulação ou mudança de resultado recusados por uma regra (R66 a R75); a mensagem vai para a tela. */
final class ContactRefused extends RuntimeException {}
