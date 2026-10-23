<?php

namespace App\Support\Contracts;

/** Enum com cor de selo na tela: success, warning, danger, info ou gray. */
interface HasColor
{
    public function getColor(): string;
}
