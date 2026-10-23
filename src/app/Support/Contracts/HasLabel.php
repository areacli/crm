<?php

namespace App\Support\Contracts;

/** Enum com rótulo para a tela. */
interface HasLabel
{
    public function getLabel(): string;
}
