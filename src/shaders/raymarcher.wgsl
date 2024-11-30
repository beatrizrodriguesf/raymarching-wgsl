const THREAD_COUNT = 16;
const PI = 3.1415927f;
const MAX_DIST = 1000.0;

@group(0) @binding(0)  
  var<storage, read_write> fb : array<vec4f>;

@group(1) @binding(0)
  var<storage, read_write> uniforms : array<f32>;

@group(2) @binding(0)
  var<storage, read_write> shapesb : array<shape>;

@group(2) @binding(1)
  var<storage, read_write> shapesinfob : array<vec4f>;

struct shape {
  transform : vec4f, // xyz = position
  radius : vec4f, // xyz = scale, w = global scale
  rotation : vec4f, // xyz = rotation
  op : vec4f, // x = operation, y = k value, z = repeat mode, w = repeat offset
  color : vec4f, // xyz = color
  animate_transform : vec4f, // xyz = animate position value (sin amplitude), w = animate speed
  animate_rotation : vec4f, // xyz = animate rotation value (sin amplitude), w = animate speed
  quat : vec4f, // xyzw = quaternion
  transform_animated : vec4f, // xyz = position buffer
};

struct march_output {
  color : vec3f,
  depth : f32,
  outline : bool,
};

fn op_smooth_union(d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  var k_eps = max(k, 0.0001);
  var h = clamp(0.5 + 0.5 * (d2 - d1) / k_eps, 0.0, 1.0);
  var d = mix(d2, d1, h) - k_eps * h * (1.0 - h);
  var col = mix(col2, col1, h);
  return vec4f(col, d);
}

fn op_smooth_subtraction(d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  var k_eps = max(k, 0.0001);
  var h = clamp(0.5 - 0.5 * (d2 + d1) / k_eps, 0.0, 1.0);
  var d = mix(d2, -d1, h) + k_eps * h * (1.0 - h);
  var col = mix(col2, col1, h);
  return vec4f(col, d);
}

fn op_smooth_intersection(d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  var k_eps = max(k, 0.0001);
  var h = clamp(0.5 - 0.5 * (d2 - d1) / k_eps, 0.0, 1.0);
  var d = mix(d2, d1, h) + k_eps * h * (1.0 - h);
  var col = mix(col2, col1, h);
  return vec4f(col, d);
}

fn op(op: f32, d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  // union
  if (op < 1.0)
  {
    return op_smooth_union(d1, d2, col1, col2, k);
  }

  // subtraction
  if (op < 2.0)
  {
    return op_smooth_subtraction(d2, d1, col2, col1, k);
  }

  // intersection
  return op_smooth_intersection(d2, d1, col2, col1, k);
}

fn repeat(p: vec3f, offset: vec3f) -> vec3f
{
    return p - offset * floor((p + 0.5 * offset) / offset);
}

fn transform_p(p: vec3f, option: vec2f) -> vec3f
{
  // normal mode
  if (option.x <= 1.0)
  {
    return p;
  }

  // return repeat / mod mode
  return repeat(p, vec3f(option.y));
}

fn scene(p: vec3f) -> vec4f // xyz = color, w = distance
{
    var d = mix(100.0, p.y, uniforms[17]);
    var time = uniforms[0];

    var spheresCount = i32(uniforms[2]);
    var boxesCount = i32(uniforms[3]);
    var torusCount = i32(uniforms[4]);

    var all_objects_count = spheresCount + boxesCount + torusCount;
    var result = vec4f(vec3f(1.0), d);

    var color = vec3f(1.0);

    for (var i = 0; i < all_objects_count; i = i + 1)
    {
      var shapeinfo = shapesinfob[i];
      var shapetype = shapeinfo[0]; // shape type (0: sphere, 1: box, 2: torus)
      var shapeindex = shapeinfo[1]; // shape index

      if (shapetype == 0) {
        var sphere = shapesb[i32(shapeindex)];

        var centerx = sphere.transform[0] - sphere.animate_transform[0]*cos(sphere.animate_transform[3]*time);
        var centery = sphere.transform[1] - sphere.animate_transform[1]*sin(sphere.animate_transform[3]*time);
        var centerz = sphere.transform[2] - sphere.animate_transform[2]*sin(sphere.animate_transform[3]*time);

        var center = vec3f(centerx, centery, centerz);

        var p_transform = transform_p(p, sphere.op.zw);
        var p_animation = p_transform - center;

        var d_object = sdf_sphere(p_animation, sphere.radius, sphere.quat);

        var result_op = op(sphere.op.x, d, d_object, color, sphere.color.xyz, sphere.op.y);
        d = result_op.w;
        color = result_op.xyz;

        if (d_object < result.w) {
          result = vec4f(color, d);
        }
      }

      else if (shapetype == 1) {
        var box = shapesb[i32(shapeindex)];

        var rotatex = box.rotation[0] - box.animate_rotation[0]*cos(box.animate_rotation[3]*time);
        var rotatey = box.rotation[1] - box.animate_rotation[1]*sin(box.animate_rotation[3]*time);
        var rotatez = box.rotation[2] - box.animate_rotation[2]*sin(box.animate_rotation[3]*time);

        var quaternion = quaternion_from_euler(vec3f(rotatex, rotatey, rotatez));

        var centerx = box.transform[0] - box.animate_transform[0]*sin(box.animate_transform[3]*time);
        var centery = box.transform[1] - box.animate_transform[1]*sin(box.animate_transform[3]*time);
        var centerz = box.transform[2] - box.animate_transform[2]*sin(box.animate_transform[3]*time);

        var center = vec3f(centerx, centery, centerz);

        var size = vec3f(box.radius[0], box.radius[1], box.radius[2]);

        var p_transform = transform_p(p, box.op.zw);
        var p_animation = rotate_vector(p_transform - center, quaternion);

        var d_object = sdf_round_box(p_animation, size, box.radius[3], box.quat);

        var result_op = op(box.op.x, d, d_object, color, box.color.xyz, box.op.y);
        d = result_op.w;
        color = result_op.xyz;

        if (d_object < result.w) {
          result = vec4f(color, d);
        }
      }

      else if (shapetype == 2) {
        var torus = shapesb[i32(shapeindex)];

        var rotatex = torus.rotation[0] - torus.animate_rotation[0]*cos(torus.animate_rotation[3]*time);
        var rotatey = torus.rotation[1] - torus.animate_rotation[1]*sin(torus.animate_rotation[3]*time);
        var rotatez = torus.rotation[2] - torus.animate_rotation[2]*sin(torus.animate_rotation[3]*time);

        var quaternion = quaternion_from_euler(vec3f(rotatex, rotatey, rotatez));

        var centerx = torus.transform[0] - torus.animate_transform[0]*sin(torus.animate_transform[3]*time);
        var centery = torus.transform[1] - torus.animate_transform[1]*sin(torus.animate_transform[3]*time);
        var centerz = torus.transform[2] - torus.animate_transform[2]*sin(torus.animate_transform[3]*time);

        var center = vec3f(centerx, centery, centerz);

        var p_transform = transform_p(p, torus.op.zw);
        var p_animation = rotate_vector(p_transform - center, quaternion);

        var d_object = sdf_torus(p_animation, vec2f(torus.radius[0], torus.radius[1]), torus.quat);

        var result_op = op(torus.op.x, d, d_object, color, torus.color.xyz, torus.op.y);
        d = result_op.w;
        color = result_op.xyz;

        if (d_object < result.w) {
          result = vec4f(color, d);
        }
      }

      // order matters for the operations, they're sorted on the CPU side

      // call transform_p and the sdf for the shape
      // call op function with the shape operation

      // op format:
      // x: operation (0: union, 1: subtraction, 2: intersection)
      // y: k value
      // z: repeat mode (0: normal, 1: repeat)
      // w: repeat offset
    }

    result = vec4f(color, d);
    return result;
}

fn march(ro: vec3f, rd: vec3f) -> march_output
{
  var max_marching_steps = i32(uniforms[5]);
  var EPSILON = uniforms[23];

  var depth = 0.0;
  var color = vec3f(1.0);
  var march_step = uniforms[22];
  var p = ro;
  var outline = false;
  
  for (var i = 0; i < max_marching_steps; i = i + 1)
  {
      // raymarch algorithm
      // call scene function and march
      var result = scene(p);
      depth += result[3];
      p = ro + depth*rd;

      // if the depth is greater than the max distance or the distance is less than the epsilon, break
      if (result[3] < EPSILON) {
        color = result.xyz;
        break;
      }
      if (result[3] < uniforms[27] && uniforms[26] == 1.0) {
        if (dot(get_normal(p),rd) < 0.03 && dot(get_normal(p),rd) > -0.03) {
          outline = true;
        }
      }
      else if (depth > MAX_DIST) {
        break;
      }
  }

  return march_output(color, depth, outline);
}

fn get_normal(p: vec3f) -> vec3f
{
  var df_x = scene(vec3f(p.x + 0.001, p.y, p.z))[3] - scene(vec3f(p.x - 0.001, p.y, p.z))[3];
  var df_y = scene(vec3f(p.x, p.y + 0.001, p.z))[3] - scene(vec3f(p.x, p.y - 0.001, p.z))[3];
  var df_z = scene(vec3f(p.x, p.y, p.z + 0.001))[3]- scene(vec3f(p.x, p.y, p.z - 0.001))[3];

  return normalize(vec3f(df_x, df_y, df_z));
}

// https://iquilezles.org/articles/rmshadows/
fn get_soft_shadow(ro: vec3f, rd: vec3f, tmin: f32, tmax: f32, k: f32) -> f32
{
  var t = tmin;  // distância mínima
  var shadow = 1.0;

  for (var i = 0; i < 50; i = i + 1) { // número de passos
      var p = ro + t * rd;
      var d = scene(p).w; // Distância do objeto mais próximo

      if (d < 0.001) { // Raio atingiu um objeto
          return 0.0;
      }

      // Atualiza o fator de sombra com base na distância e suavização
      shadow = min(shadow, k * d / t);
      t += d;

      if (t > tmax) {
          break;
      }
    }

    return shadow;
}

fn get_AO(current: vec3f, normal: vec3f) -> f32
{
  var occ = 0.0;
  var sca = 1.0;
  for (var i = 0; i < 5; i = i + 1)
  {
    var h = 0.001 + 0.15 * f32(i) / 4.0;
    var d = scene(current + h * normal).w;
    occ += (h - d) * sca;
    sca *= 0.95;
  }

  return clamp( 1.0 - 2.0 * occ, 0.0, 1.0 ) * (0.5 + 0.5 * normal.y);
}

fn get_ambient_light(light_pos: vec3f, sun_color: vec3f, rd: vec3f) -> vec3f
{
  var backgroundcolor1 = int_to_rgb(i32(uniforms[12]));
  var backgroundcolor2 = int_to_rgb(i32(uniforms[29]));
  var backgroundcolor3 = int_to_rgb(i32(uniforms[30]));
  
  var ambient = backgroundcolor1 - rd.y * rd.y * 0.5;
  ambient = mix(ambient, 0.85 * backgroundcolor2, pow(1.0 - max(rd.y, 0.0), 4.0));

  var sundot = clamp(dot(rd, normalize(vec3f(light_pos))), 0.0, 1.0);
  var sun = 0.25 * sun_color * pow(sundot, 5.0) + 0.25 * vec3f(1.0,0.8,0.6) * pow(sundot, 64.0) + 0.2 * vec3f(1.0,0.8,0.6) * pow(sundot, 512.0);
  ambient += sun;
  ambient = mix(ambient, 0.68 * backgroundcolor3, pow(1.0 - max(rd.y, 0.0), 16.0));

  return ambient;
}

fn get_light(current: vec3f, obj_color: vec3f, rd: vec3f) -> vec3f
{
  var light_position = vec3f(uniforms[13], uniforms[14], uniforms[15]);
  var sun_color = int_to_rgb(i32(uniforms[16]));
  var ambient = get_ambient_light(light_position, sun_color, rd);
  var normal = get_normal(current);

  // calculate light based on the normal
  var light_dir = normalize(light_position - current);
  var light_distance = length(current - light_position);

  // if the object is too far away from the light source, return ambient light
  if (light_distance > uniforms[20] + uniforms[8])
  {
    return ambient;
  }

  // Light intensity
  var shadow = get_soft_shadow(current, light_dir, 0.01, light_distance, 8.0); // shadow
  var direct_light = shadow * max(dot(normal, light_dir), 0.0);

  var ambient_occlusion = get_AO(current, normal); // ambient occlusion
  var ambient_light = ambient*ambient_occlusion; // ambient light

  return (direct_light + ambient_light)*obj_color;
}

fn set_camera(ro: vec3f, ta: vec3f, cr: f32) -> mat3x3<f32>
{
  var cw = normalize(ta - ro);
  var cp = vec3f(sin(cr), cos(cr), 0.0);
  var cu = normalize(cross(cw, cp));
  var cv = normalize(cross(cu, cw));
  return mat3x3<f32>(cu, cv, cw);
}

fn animate(val: vec3f, time_scale: f32, offset: f32) -> vec3f
{
  return vec3f(0.0);
}

@compute @workgroup_size(THREAD_COUNT, 1, 1)
fn preprocess(@builtin(global_invocation_id) id : vec3u)
{
  var time = uniforms[0];
  var spheresCount = i32(uniforms[2]);
  var boxesCount = i32(uniforms[3]);
  var torusCount = i32(uniforms[4]);
  var all_objects_count = spheresCount + boxesCount + torusCount;

  if (id.x >= u32(all_objects_count))
  {
    return;
  }

  // optional: performance boost
  // Do all the transformations here and store them in the buffer since this is called only once per object and not per pixel
}

@compute @workgroup_size(THREAD_COUNT, THREAD_COUNT, 1)
fn render(@builtin(global_invocation_id) id : vec3u)
{
  // unpack data
  var fragCoord = vec2f(f32(id.x), f32(id.y));
  var rez = vec2(uniforms[1]);
  var time = uniforms[0];

  // camera setup
  var lookfrom = vec3(uniforms[6], uniforms[7], uniforms[8]);
  var lookat = vec3(uniforms[9], uniforms[10], uniforms[11]);
  var camera = set_camera(lookfrom, lookat, 0.0);
  var ro = lookfrom;

  // get ray direction
  var uv = (fragCoord - 0.5 * rez) / rez.y;
  uv.y = -uv.y;
  var rd = camera * normalize(vec3(uv, 1.0));

  // call march function and get the color/depth
  var march_result = march(ro, rd);

  // move ray based on the depth
  var p = ro + march_result.depth*rd;
  var color = vec3f(1.0);

  // get light
  if (!march_result.outline) {
    color = get_light(p, march_result.color, rd);
  }
  
  // display the result
  color = linear_to_gamma(color);
  fb[mapfb(id.xy, uniforms[1])] = vec4(color, 1.0);
}