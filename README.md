## WGSL Raymarcher

Projeto de Raymarcher implementado na disciplica de computação gráfica

### Cenas implementadas:

- C: ```"Sphere", "SkyAndHS", "Multiple"```
- C+: ```"Rotation"```
- B: ```"Animation"```, ```"Outline*"```
- B+: ```"Union"```, ```"Subtraction"```, ```"Intersection"```, ```"Blobs"```
- A: ```"Mod"```, ```"SoftShadows"```

A cena Outline está com alguns artefatos, tentei de diversas formas, e a ideia final foi deixar em branco pontos que estivessem próximos ao objeto uma distância de EPSILON + tamanho do contorno e que tivessem uma normal perpendicular ao plano da câmera, assim seriam desconsiderados pontos da parte da frente da esfera por exemplo.